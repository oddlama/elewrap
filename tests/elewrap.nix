(import ./lib.nix) {
  name = "elewrap-nixos";
  nodes.machine = {
    self,
    pkgs,
    ...
  }: let
    showArguments = pkgs.writeShellScript "show-arguments" ''
      ARGS=("$@")
      printf "%s\n" "''${ARGS[*]@Q}"
    '';
  in {
    imports = [self.nixosModules.default];
    nixpkgs.overlays = [self.overlays.default];

    # Test root privilege escalation
    security.elewrap.id-as-root = {
      command = ["${pkgs.coreutils}/bin/id"];
      targetUser = "root";
      allowedUsers = ["test1"];
    };

    # Test user change and allowedGroups
    security.elewrap.id-as-test2 = {
      command = ["${pkgs.coreutils}/bin/id"];
      targetUser = "test2";
      allowedUsers = ["test1"];
      allowedGroups = ["group1"];
    };

    # Test user change with supplementary groups
    security.elewrap.id-as-test3 = {
      command = ["${pkgs.coreutils}/bin/id"];
      targetUser = "test3";
      allowedUsers = ["test1"];
    };

    # Ensure that extra arguments are ignored by default
    security.elewrap.show-args-ignore-extra = {
      command = [showArguments "--compiledArg1" "--compiledArg2"];
      targetUser = "test1";
      allowedUsers = ["test1"];
    };

    # Ensure that extra arguments can be passed if explicitly allowed
    security.elewrap.show-args-allow-extra = {
      command = [showArguments "--compiledArg1" "--compiledArg2"];
      targetUser = "test1";
      allowedUsers = ["test1"];
      passRuntimeArguments = true;
    };

    # Ensure that environment is forced empty by default
    security.elewrap.show-env-allow-none = {
      command = ["${pkgs.coreutils}/bin/env"];
      targetUser = "test1";
      allowedUsers = ["test1"];
    };

    # Ensure that specific environment variables can be passed
    security.elewrap.show-env-allow-var = {
      command = ["${pkgs.coreutils}/bin/env"];
      targetUser = "test1";
      allowedUsers = ["test1"];
      passEnvironment = ["VAR"];
    };

    # Ensure that LD_PRELOAD is always removed (should be done by ld.so.1 due to CAP_SETUID)
    security.elewrap.show-env-allow-ld = {
      command = ["${pkgs.coreutils}/bin/env"];
      targetUser = "test1";
      allowedUsers = ["test1"];
      passEnvironment = ["LD_PRELOAD"];
    };

    # Ensure that the delimiter character does not appear in the command

    users.users.test1.group = "test1";
    users.users.test1.uid = 801;
    users.groups.test1.gid = 801;

    users.users.test2.group = "test2";
    users.users.test2.uid = 802;
    users.groups.test2.gid = 802;

    users.users.test3.group = "test3";
    users.users.test3.uid = 803;
    users.groups.test3.gid = 803;

    users.groups.group1.members = ["test3"];
    users.groups.group1.gid = 901;
    users.groups.group2.members = ["test3"];
    users.groups.group2.gid = 902;
  };

  testScript = ''
    start_all()

    # wait for our service to start
    machine.wait_for_unit("multi-user.target")

    def expect_output(output, expected):
      assert output == expected, f"""
        Expected output: {repr(expected)}
        Actual output: {repr(output)}
      """

    output = machine.succeed("runuser -u test1 -- /run/wrappers/bin/elewrap-id-as-root")
    expect_output(output, "uid=0(root) gid=0(root) groups=0(root)\n")
    machine.fail("runuser -u root -- /run/wrappers/bin/elewrap-id-as-root")
    machine.fail("runuser -u test2 -- /run/wrappers/bin/elewrap-id-as-root")
    machine.fail("runuser -u test3 -- /run/wrappers/bin/elewrap-id-as-root")

    output = machine.succeed("runuser -u test1 -- /run/wrappers/bin/elewrap-id-as-test2")
    expect_output(output, "uid=802(test2) gid=802(test2) groups=802(test2)\n")
    machine.fail("runuser -u root -- /run/wrappers/bin/elewrap-id-as-test2")
    machine.fail("runuser -u test2 -- /run/wrappers/bin/elewrap-id-as-test2")
    output = machine.succeed("runuser -u test3 -- /run/wrappers/bin/elewrap-id-as-test2")
    expect_output(output, "uid=802(test2) gid=802(test2) groups=802(test2)\n")

    output = machine.succeed("runuser -u test1 -- /run/wrappers/bin/elewrap-id-as-test3")
    expect_output(output, "uid=803(test3) gid=803(test3) groups=803(test3),901(group1),902(group2)\n")
    machine.fail("runuser -u root -- /run/wrappers/bin/elewrap-id-as-test3")
    machine.fail("runuser -u test2 -- /run/wrappers/bin/elewrap-id-as-test3")
    machine.fail("runuser -u test3 -- /run/wrappers/bin/elewrap-id-as-test3")

    output = machine.succeed("runuser -u test1 -- /run/wrappers/bin/elewrap-show-args-ignore-extra")
    expect_output(output, "'--compiledArg1' '--compiledArg2'\n")
    output = machine.succeed("runuser -u test1 -- /run/wrappers/bin/elewrap-show-args-ignore-extra --extra1 --extra2")
    expect_output(output, "'--compiledArg1' '--compiledArg2'\n")

    output = machine.succeed("runuser -u test1 -- /run/wrappers/bin/elewrap-show-args-allow-extra")
    expect_output(output, "'--compiledArg1' '--compiledArg2'\n")
    output = machine.succeed("runuser -u test1 -- /run/wrappers/bin/elewrap-show-args-allow-extra --extra1 --extra2")
    expect_output(output, "'--compiledArg1' '--compiledArg2' '--extra1' '--extra2'\n")

    output = machine.succeed("runuser -u test1 -- sh -c '/run/wrappers/bin/elewrap-show-env-allow-none'")
    expect_output(output, "")
    output = machine.succeed("runuser -u test1 -- sh -c 'VAR=1 /run/wrappers/bin/elewrap-show-env-allow-none'")
    expect_output(output, "")

    output = machine.succeed("runuser -u test1 -- sh -c '/run/wrappers/bin/elewrap-show-env-allow-var'")
    expect_output(output, "")
    output = machine.succeed("runuser -u test1 -- sh -c 'VAR=1 /run/wrappers/bin/elewrap-show-env-allow-var'")
    expect_output(output, "VAR=1\n")

    output = machine.succeed("runuser -u test1 -- sh -c '/run/wrappers/bin/elewrap-show-env-allow-ld'")
    expect_output(output, "")
    output = machine.succeed("runuser -u test1 -- sh -c 'LD_PRELOAD=/lib/dummy.so /run/wrappers/bin/elewrap-show-env-allow-ld'")
    expect_output(output, "")
  '';
}
