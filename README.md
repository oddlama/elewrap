## About

Transparently wraps a program to allow for controlled elevation of privileges.
The authentication rules are kept simple and will be baked in at compile-time,
cutting down any attack surface to the absolute bare minimum.

The resulting executable should either be owned by root:root or even better
be owned by the target user directly. Permissions should be 6001 (setuid+setgid, only allow execution by everyone)
or 6401 in case you want to verify the sha512 of the binary before executing it.
