crane: pkgs: let
  craneLib = crane.mkLib pkgs;
  inherit (pkgs) lib;
  src = craneLib.cleanCargoSource (craneLib.path ./..);

  commonArgs = {
    inherit src;

    buildInputs =
      [
        # Add additional build inputs here
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        # Additional darwin specific inputs can be set here
        pkgs.libiconv
      ];
  };

  # Build *just* the cargo dependencies, so we can reuse
  # all of that work (e.g. via cachix) when running in CI
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

  # Generates the necessary environment variables to allow building
  # elewrap for the given command and options.
  mkElewrapEnvironment = {
    targetUser,
    command,
    commandDelimiter ? "\t",
    allowedUsers ? [],
    allowedGroups ? [],
    passEnvironment ? [],
    passArguments ? false,
    verifySha512 ? true,
    ...
  }:
    {
      # XXX: assert commandDelimiter not in any element of command
      inherit cargoArtifacts;
      ELEWRAP_TARGET_USER = targetUser;
      ELEWRAP_TARGET_COMMAND = lib.concatStringsSep commandDelimiter command;
      ELEWRAP_TARGET_COMMAND_DELIMITER = commandDelimiter;
      ELEWRAP_PASS_ARGUMENTS = toString passArguments;
    }
    // lib.optionalAttrs (passEnvironment != []) {
      ELEWRAP_PASS_ENVIRONMENT = lib.concatStringsSep "," passEnvironment;
    }
    // lib.optionalAttrs verifySha512 {
      ELEWRAP_TARGET_COMMAND_SHA512 = builtins.hashFile "sha512" (lib.head command);
    }
    // lib.optionalAttrs (allowedUsers != []) {
      ELEWRAP_ALLOWED_USERS = lib.concatStringsSep "," allowedUsers;
    }
    // lib.optionalAttrs (allowedGroups != []) {
      ELEWRAP_ALLOWED_GROUPS = lib.concatStringsSep "," allowedGroups;
    };

  # Wrapper function that generates a derivation for
  # the given settings. Refer to mkElewrapEnvironment for
  # available settings.
  mkElewrap = {extraCraneArgs ? {}, ...} @ args: craneLib.buildPackage (commonArgs // mkElewrapEnvironment args // extraCraneArgs);

  # A dummy environment that can be used to test compilation
  # and to have a functioning development setup.
  dummyElewrapEnvironment = mkElewrapEnvironment {
    targetUser = "root";
    command = ["${pkgs.coreutils}/bin/id"];
  };
in {
  inherit
    cargoArtifacts
    commonArgs
    dummyElewrapEnvironment
    mkElewrap
    mkElewrapEnvironment
    src
    ;
}
