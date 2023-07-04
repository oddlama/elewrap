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

        passEnvironment = mkOption {
          default = [];
          type = types.listOf types.str;
          description = "The environment variables in this list will be allowed to be passed to the target command. Anything else will be erased.";
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
              passRuntimeArguments
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
