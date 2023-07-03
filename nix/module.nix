inputs: {
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    head
    isPath
    literalExpression
    mkOption
    types
    ;
in {
  options.security.elewrap = mkOption {
    default = {};
    example = literalExpression ''
      {
        sensors = {
          source = "''${pkgs.lm-sensors}/bin/sensors";
          targetUser = "root";
          allowedUsers = ["telegraf" "prometheus"];
        };
      }
    '';
    description = ''
      Transparently wraps a program to allow for controlled elevation of privileges.
      Like sudo, doas or please but the authentication rules are kept simple and will
      be baked into the wrapper at compile-time, cutting down any attack surface
      to the absolute bare minimum.
    '';
    type = types.attrsOf (types.submodule ({config, ...}: {
      options = {
        wrapper = mkOption {
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
          description = "The command that is wrapped and executed by calling.";
        };

        targetUser = mkOption {
          type = types.str;
          description = "The user to elevate to, before executing the command.";
        };

        allowedUsers = mkOption {
          default = [];
          type = types.listOf types.str;
          description = "The users allowed to execute this wrapper.";
        };

        allowedGroups = mkOption {
          default = [];
          type = types.listOf types.str;
          description = "The .";
        };

        passRuntimeArguments = mkOption {
          default = false;
          type = types.bool;
          description = "Whether any given runtime arguments should be appended to the target command.";
        };

        verifySha512 = mkOption {
          default = true;
          type = types.bool;
          description = "Whether to verify the sha512 of the target executable at runtime before executing it.";
        };
      };

      config = {
        assertions = [
          {
            assertion = (config.allowedUsers == []) != (config.allowedGroups == []);
            message = "security.elewrap.${config._module.args.name}: Either allowedUsers or allowedGroups must be set!";
          }
          {
            assertion = isPath (head config.command);
            message = "security.elewrap.${config._module.args.name}: The command executable must be a path!";
          }
        ];

        security.wrappers."elewrap-${config._module.args.name}" = {
          source = pkgs.mkElewrap {
            inherit
              (config)
              allowedGroups
              allowedUsers
              command
              passRuntimeArguments
              targetUser
              verifySha512
              ;
            extraCraneArgs.pnameSuffix = "-${config._module.args.name}";
          };
          setuid = true;
          owner = config.targetUser;
          group = "root";
          # Allow anyone to execute this, elewrap will take care of authenticating the user.
          # Also allow read permissions to the setuid user so the sha512 can be verified
          # before executing the target program.
          permissions =
            if config.verifySha512
            then "401"
            else "001";
        };
      };
    }));
  };
}
