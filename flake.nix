{
  description = "TODO";
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
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      inherit (pkgs) lib;
      craneLib = crane.lib.${system};

      src = craneLib.cleanCargoSource (craneLib.path ./.);

      buildInputs =
        [
          # Add additional build inputs here
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          # Additional darwin specific inputs can be set here
          pkgs.libiconv
        ];

      # Build *just* the cargo dependencies, so we can reuse
      # all of that work (e.g. via cachix) when running in CI
      cargoArtifacts = craneLib.buildDepsOnly {
        inherit src buildInputs;
      };

      # Build the actual crate itself, reusing the dependency
      # artifacts from above.
      elewrap = craneLib.buildPackage {
        inherit src buildInputs cargoArtifacts;
      };
    in {
      checks =
        {
          # Build the crate as part of `nix flake check` for convenience
          inherit elewrap;

          # Run clippy (and deny all warnings) on the crate source,
          # again, resuing the dependency artifacts from above.
          #
          # Note that this is done as a separate derivation so that
          # we can block the CI if there are issues here, but not
          # prevent downstream consumers from building our crate by itself.
          elewrap-clippy = craneLib.cargoClippy {
            inherit src buildInputs cargoArtifacts;
            cargoClippyExtraArgs = "--all-targets -- --deny warnings";
          };

          elewrap-doc = craneLib.cargoDoc {
            inherit src buildInputs cargoArtifacts;
          };

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
          elewrap-nextest = craneLib.cargoNextest {
            inherit src buildInputs cargoArtifacts;
            partitions = 1;
            partitionType = "count";
          };

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
          elewrap-coverage = craneLib.cargoTarpaulin {
            inherit src buildInputs cargoArtifacts;
          };
        };

      formatter = pkgs.alejandra; # `nix fmt`

      packages.default = elewrap; # `nix build`
      packages.elewrap = elewrap; # `nix build .#elewrap`

      # `nix run`
      apps.default = flake-utils.lib.mkApp {drv = elewrap;};

      # `nix develop`
      devShells.default = pkgs.mkShell {
        inherit (self.checks.${system}.pre-commit) shellHook;
        inputsFrom = lib.attrValues self.checks.${system};
        buildInputs =
          buildInputs
          ++ (with pkgs; [cargo rustc rustfmt]);
      };
    });
}
