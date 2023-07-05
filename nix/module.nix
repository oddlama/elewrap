inputs: {
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    attrNames
    concatLists
    flip
    head
    literalExpression
    mapAttrs'
    mapAttrsToList
    mkOption
    nameValuePair
    pathExists
    types
    ;

  cfg = config.security.elewrap;
in {
  options.security.elewrap = mkOption {
    default = {};
    example = literalExpression ''
      {
        sensors = {
          # We already specify the necessary parameters here and
          # (by default) ignore any arguments passed at runtime
          command = ["${pkgs.lm_sensors}/bin/sensors" "-A" "-u"];
          # Run as root
          targetUser = "root";
          # Only allow telegraf to elevate privileges
          allowedUsers = ["telegraf"];
        };
      }
    '';
    description = ''
      Transparently wraps programs to allow controlled elevation of privileges.
      Like sudo, doas or please but the authentication rules are kept simple and will
      be baked into the wrapper at compile-time, cutting down any attack surface
      to the absolute bare minimum.
    '';
    type = types.attrsOf (types.submodule ({config, ...}: {
      options = {
        path = mkOption {
          type = types.str;
          readOnly = true;
          default = "/run/wrappers/bin/elewrap-${config._module.args.name}";
          description = ''
            The resulting wrapper that may be executed by the allowed users and groups
            to run the given command with elevated permissions.
          '';
        };

        command = mkOption {
          type = types.listOf (types.either types.str types.path);
          example = literalExpression ''["''${pkgs.lm_sensors}/bin/sensors"]'';
          description = ''
            The command that is executed after elevating privileges.
            May include arguments. The first element (the executable) must be a path.
          '';
        };

        targetUser = mkOption {
          type = types.str;
          example = "root";
          description = "The user to change to before executing the command.";
        };

        allowedUsers = mkOption {
          default = [];
          example = ["user1" "user2"];
          type = types.listOf types.str;
          description = "The users allowed to execute this wrapper.";
        };

        allowedGroups = mkOption {
          default = [];
          example = ["group1" "group2"];
          type = types.listOf types.str;
          description = "The groups allowed to execute this wrapper.";
        };

        passEnvironment = mkOption {
          default = [];
          type = types.listOf types.str;
          description = "The environment variables in this list will be allowed to be passed to the target command. Anything else will be erased.";
        };

        passArguments = mkOption {
          default = false;
          type = types.bool;
          description = ''
            Whether any given arguments should be appended to the target command.
            This will be added to any static arguments given in the command, if any.
          '';
        };

        verifySha512 = mkOption {
          default = true;
          type = types.bool;
          description = "Whether to verify the sha512 of the target executable at runtime before executing it.";
        };
      };
    }));
  };

  config = {
    assertions = concatLists (flip mapAttrsToList cfg (name: elewrapCfg: [
      {
        assertion = elewrapCfg.allowedUsers != [] || elewrapCfg.allowedGroups != [];
        message = "security.elewrap.${name}: Either allowedUsers or allowedGroups must be set!";
      }
      {
        assertion = pathExists (head elewrapCfg.command);
        message = "security.elewrap.${name}: The command executable must be an existing path!";
      }
    ]));

    nixpkgs.overlays = [inputs.self.overlays.default];

    security.wrappers = flip mapAttrs' cfg (name: elewrapCfg:
      nameValuePair "elewrap-${name}" {
        source = let
          drv = pkgs.mkElewrap {
            inherit
              (elewrapCfg)
              allowedGroups
              allowedUsers
              command
              passEnvironment
              passArguments
              targetUser
              verifySha512
              ;
            extraCraneArgs.pnameSuffix = "-${name}";
          };
        in "${drv}/bin/elewrap";

        setuid = true;
        owner = "root";
        group = "root";
        # Allow anyone to execute this, elewrap will take care of authenticating the user.
        # Also allow read permissions to the setuid user so the sha512 can be verified
        # before executing the target program.
        permissions =
          if elewrapCfg.verifySha512
          then "u+r,o+x"
          else "o+x";
      });
  };
}
