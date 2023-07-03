{
  description = "👑 Controlled static privilege escalation utility with baked-in authentication rules. The most restrictive and lightweight replacement for sudo, doas or please.";
  inputs = {
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = {
    self,
    advisory-db,
    crane,
    flake-utils,
    nixpkgs,
    pre-commit-hooks,
  } @ inputs:
    {
      # Expose NixOS module
      nixosModules.elewrap = import ./nix/module.nix inputs;
      nixosModules.default = self.nixosModules.elewrap;

      # A nixpkgs overlay that adds the parametrized builder as a package
      overlays.default = self.overlays.elewrap;
      overlays.elewrap = final: prev: {
        inherit (import ./nix/elewrap.nix crane prev.pkgs) mkElewrap;
      };
    }
    // flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      inherit (pkgs) lib;
      craneLib = crane.lib.${system};

      inherit
        (import ./nix/elewrap.nix crane pkgs)
        cargoArtifacts
        commonArgs
        dummyElewrapEnvironment
        src
        ;

      # Add environment variables to allow a successful compile
      checkArgs = commonArgs // dummyElewrapEnvironment;
    in {
      checks =
        {
          # Build a dummy crate as part of `nix flake check` for convenience
          elewrapDummy = craneLib.buildPackage checkArgs;

          # Run clippy (and deny all warnings) on the crate source,
          # again, resuing the dependency artifacts from above.
          #
          # Note that this is done as a separate derivation so that
          # we can block the CI if there are issues here, but not
          # prevent downstream consumers from building our crate by itself.
          elewrap-clippy = craneLib.cargoClippy (checkArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            });

          elewrap-doc = craneLib.cargoDoc (checkArgs
            // {
              inherit cargoArtifacts;
            });

          # Check formatting
          elewrap-fmt = craneLib.cargoFmt {
            inherit src;
          };

          # Audit dependencies
          elewrap-audit = craneLib.cargoAudit {
            inherit src advisory-db;
          };

          # Run tests with cargo-nextest
          # Consider setting `doCheck = false` on `elewrap` if you do not want
          # the tests to run twice
          elewrap-nextest = craneLib.cargoNextest (checkArgs
            // {
              inherit cargoArtifacts;
              partitions = 1;
              partitionType = "count";
            });

          pre-commit = pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              alejandra.enable = true;
              cargo-check.enable = true;
              rustfmt.enable = true;
              statix.enable = true;
            };
          };
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          # NB: cargo-tarpaulin only supports x86_64 systems
          # Check code coverage (note: this will not upload coverage anywhere)
          elewrap-coverage = craneLib.cargoTarpaulin (checkArgs
            // {
              inherit cargoArtifacts;
            });
        };

      # `nix develop`
      devShells.default = pkgs.mkShell (dummyElewrapEnvironment
        // {
          inherit (self.checks.${system}.pre-commit) shellHook;
          inputsFrom = lib.attrValues self.checks.${system};
          buildInputs =
            commonArgs.buildInputs
            ++ (with pkgs; [cargo rustc rustfmt statix]);
        });

      formatter = pkgs.alejandra; # `nix fmt`
    });
}
