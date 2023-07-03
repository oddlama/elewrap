## 👑 About

Transparently wraps a program to allow for controlled elevation of privileges.
The authentication rules are kept simple and will be baked in at compile-time,
cutting down any attack surface to the absolute bare minimum.
An alternative to sudo, doas or please but without any dynamic configuration
in just 100 lines of code.

The resulting executable should either be owned by root:root or even better
be owned by target_user:root. Permissions should be 4001 (setuid; only allow execution by everyone)
or 4401 in case you want to verify the sha512 of the binary before executing it.

Includes a NixOS module to allow declaring wrappers easily and can be used to replace
sudo, doas or please with elewrap as a more minimal alternative.

# TODO nixos tests
