{
  inputs = {
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    nci = {
      url = "github:yusdacra/nix-cargo-integration";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devshell.flakeModule
        inputs.flake-parts.flakeModules.easyOverlay
        inputs.nci.flakeModule
        inputs.pre-commit-hooks.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      flake =
        { config, ... }:
        {
          nixosModules.default = {
            imports = [ ./nix/nixosModules/elewrap.nix ];
            nixpkgs.overlays = [ config.overlays.default ];
          };
        };

      perSystem =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          projectName = "elewrap";

          # Generates the necessary environment variables to allow building
          # elewrap for the given command and options.
          mkElewrapEnvironment =
            {
              targetUser,
              command,
              commandDelimiter ? "\t",
              allowedUsers ? [ ],
              allowedGroups ? [ ],
              passEnvironment ? [ ],
              passArguments ? false,
              verifySha512 ? true,
              ...
            }:
            {
              # XXX: assert commandDelimiter not in any element of command
              ELEWRAP_TARGET_USER = targetUser;
              ELEWRAP_TARGET_COMMAND = lib.concatStringsSep commandDelimiter command;
              ELEWRAP_TARGET_COMMAND_DELIMITER = commandDelimiter;
              ELEWRAP_PASS_ARGUMENTS = toString passArguments;
            }
            // lib.optionalAttrs (passEnvironment != [ ]) {
              ELEWRAP_PASS_ENVIRONMENT = lib.concatStringsSep "," passEnvironment;
            }
            // lib.optionalAttrs verifySha512 {
              ELEWRAP_TARGET_COMMAND_SHA512 = builtins.hashFile "sha512" (lib.head command);
            }
            // lib.optionalAttrs (allowedUsers != [ ]) {
              ELEWRAP_ALLOWED_USERS = lib.concatStringsSep "," allowedUsers;
            }
            // lib.optionalAttrs (allowedGroups != [ ]) {
              ELEWRAP_ALLOWED_GROUPS = lib.concatStringsSep "," allowedGroups;
            };

          # A dummy environment that can be used to test compilation
          # and to have a functioning development setup.
          dummyElewrapEnvironment = mkElewrapEnvironment {
            targetUser = "root";
            command = [ "${pkgs.coreutils}/bin/id" ];
          };
        in
        {
          devshells.default = {
            packages = [
              config.treefmt.build.wrapper
              pkgs.cargo-release
            ];

            env = lib.mapAttrsToList (name: value: { inherit name value; }) dummyElewrapEnvironment;
            devshell.startup.pre-commit.text = config.pre-commit.installationScript;
          };

          pre-commit.settings.hooks.treefmt.enable = true;
          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              deadnix.enable = true;
              statix.enable = true;
              nixfmt.enable = true;
              rustfmt.enable = true;
            };
          };

          nci.projects.${projectName} = {
            path = ./.;
            numtideDevshell = "default";
          };
          nci.crates.${projectName} = {
            # Wrapper function that generates a elewrap binary for the given settings.
            # Refer to mkElewrapEnvironment for available settings.
            drvConfig.public.mkElewrap =
              elewrapConfig:
              config.nci.outputs.${projectName}.packages.release.out.overrideAttrs (prev: {
                pname = prev.pname + lib.optionalString (elewrapConfig ? name) "-${elewrapConfig.name}";
                env = mkElewrapEnvironment elewrapConfig;
              });
          };

          packages.default = config.nci.outputs.${projectName}.packages.release;
          packages.nixosTest = import ./nix/tests/elewrap.nix {
            inherit (inputs) self;
            inherit pkgs lib;
          };

          overlayAttrs.elewrap = config.packages.default;
        };
    };
}
