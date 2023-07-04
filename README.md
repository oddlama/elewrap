## 👑 About

Transparently wraps a program to allow for controlled elevation of privileges.
The authentication rules are kept simple and will be baked in at compile-time,
cutting down any attack surface to the absolute bare minimum.
An alternative to sudo, doas or please but without any dynamic configuration
in just 100 lines of code.

The resulting executable should be owned by root:root and have the setuid bit
set (or be executed with CAP_SETUID). Permissions should therefore be 4001 (setuid; allow execution by everyone, no read/write).

Includes a NixOS module to allow declaring wrappers easily and can be used to replace
sudo, doas or please with elewrap as a more minimal alternative.
