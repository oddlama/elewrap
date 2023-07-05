[Building](#building) \| [Installation](#installation-and-usage-on-nixos) \| [Module options](#module-options)

## 🥙 Elewrap

This is a tiny setuid wrapper program allowing for controlled elevation of privileges,
similar to sudo, doas or please but with significantly less complexity and no dynamic configuration.
The authentication rules are kept simple and will be baked in at compile-time,
cutting down any attack surface to the absolute bare minimum.

- 🔐 All authentication rules will be baked in.
- ❄️ Provides a NixOS module to easily declare wrappers using elewrap to get rid of sudo.
- 🌱 Tiny and simple program that is easy to audit. [See for yourself](./src/main.rs).

## Building

You can build an elewrap wrapper simply by cloning this repository and running cargo build:

```bash
# Export variables (see below)
$ cargo build
```

To set the authentication rules and target command, you will have to export
some environment variables before building. These variables are available:

| Variable | Type | Default | Description |
|---|---|---|---|
`ELEWRAP_TARGET_USER` | Required | - | The target user to change to before executing the command.
`ELEWRAP_TARGET_COMMAND` | Required | - | The command to execute after changing to the target user. The executable path be absolute. The given string will be split on configured delimiter to allow defining arguments.
`ELEWRAP_TARGET_COMMAND_DELIMITER` | Optional | `"\t"` | The delimiter on which to split the target command.
`ELEWRAP_TARGET_COMMAND_SHA512` | Optional | Unset | If set, authenticates the target binary based on its sha512 hash before executing it.
`ELEWRAP_ALLOWED_USERS` | Optional | Unset (empty list) |  A comma separated list of users for which to allow elevation of privileges using this utility. Leave unset for an empty list.
`ELEWRAP_ALLOWED_GROUPS` | Optional | Unset (empty list) | A comma separated list of groups for which to allow elevation of privileges using this utility. Leave unset for an empty list.
`ELEWRAP_PASS_ENVIRONMENT` | Optional | Unset (empty list) | A comma separated list of environment variables which should be allowed to be passed to the target command.
`ELEWRAP_PASS_ARGUMENTS` | Optional | `false` | Whether any additional runtime arguments should be appended to the executed command.

Afterwards, it is recommended to rename the executable to be able to identify the target command in case several wrappers are built.
The ownership of the resulting executable must then be given to `root:root` and the setuid bit must
be set. Ideally, set the permissions `4001` to allow execution by anyone while denying any read or write attempts.

## Installation and Usage on NixOS

This project's flake.nix exposes a module to simplify usage on NixOS.
To use it, add elewrap to your own `flake.nix` and use the module in your nixos system configurations.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    elewrap.url = "github:oddlama/elewrap";
    elewrap.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, elewrap }: {
    # Add the module to your system(s)
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        elewrap.nixosModules.default
      ];
    };
  };
}
```

Lets say you now want to allow `telegraf` to run `sensors` with elevated permissions.
This is achieved simply by defining a new wrapper for the target executable in `security.elewrap` and
pointing telegraf to the new executable.

```nix
{ config, ... }: {
  # Define a new wrapper to elevate privileges, refer to the module
  # options for more information about the options.
  security.elewrap.sensors = {
    # We already specify the necessary parameters here
    # and (by default) ignore any arguments passed at runtime
    command = ["${pkgs.lm-sensors}/bin/sensors" "-A" "-u"];
    # Run as root
    targetUser = "root";
    # Only allow telegraf to elevate privileges
    allowedUsers = ["telegraf"];
  };

  # Set the path for the sensors executable to the resulting wrapper
  services.telegraf.extraConfig.inputs.sensors.path = config.security.elewrap.sensors.path;
}
```

## ❄️ Module options

## `security.elewrap`

Transparently wraps programs to allow controlled elevation of privileges.
Like sudo, doas or please but the authentication rules are kept simple and will
be baked into the wrapper at compile-time, cutting down any attack surface
to the absolute bare minimum.

## `security.elewrap.<name>.path`

| Type    | `str` |
|---------|-----|

The resulting wrapper that may be executed by the allowed users and groups
to run the given command with elevated permissions.

## `security.elewrap.<name>.command`

| Type    | `listOf (either str path)` |
|---------|-----|
| Example | `["${pkgs.lm-sensors}/bin/sensors"]` |

The command that is executed after elevating privileges.
May include arguments. The first element (the executable) must be a path.

## `security.elewrap.<name>.targetUser`

| Type    | `str` |
|---------|-----|
| Example | `"root"` |

The user to change to before executing the command.

## `security.elewrap.<name>.allowedUsers`

| Type    | `listOf str` |
|---------|-----|
| Default | `[]` |
| Example | `["user1" "user2"]` |

The users allowed to execute this wrapper.

## `security.elewrap.<name>.allowedGroups`

| Type    | `listOf str` |
|---------|-----|
| Default | `[]` |
| Example | `["group1" "group2"]` |

The groups allowed to execute this wrapper.

## `security.elewrap.<name>.passEnvironment`

| Type    | `listOf str` |
|---------|-----|
| Default | `[]` |
| Example | `["SOME_ALLOWED_VAR"]` |

The environment variables in this list will be allowed to be passed
to the target command. Anything else will be erased.

## `security.elewrap.<name>.passArguments`

| Type    | `listOf str` |
|---------|-----|
| Default | `false` |

Whether any given arguments should be appended to the target command.
This will be added to any static arguments given in the command, if any.

## `security.elewrap.<name>.verifySha512`

| Type    | `listOf str` |
|---------|-----|
| Default | `true` |

Whether to verify the sha512 of the target executable at runtime before executing it.
