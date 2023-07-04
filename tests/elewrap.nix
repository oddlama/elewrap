(import ./lib.nix) {
  name = "elewrap-nixos";
  nodes.machine = {
    self,
    pkgs,
    ...
  }: {
    imports = [self.nixosModules.default];
    nixpkgs.overlays = [self.overlays.default];

    # Test root privilege escalation
    security.elewrap.id-as-root = {
      command = ["${pkgs.coreutils}/bin/id"];
      targetUser = "root";
      allowedUsers = ["test1"];
    };

    # Test user change
    security.elewrap.id-as-test2 = {
      command = ["${pkgs.coreutils}/bin/id"];
      targetUser = "test2";
      allowedUsers = ["test1"];
    };

    # Test user change with supplementary groups
    security.elewrap.id-as-test3 = {
      command = ["${pkgs.coreutils}/bin/id"];
      targetUser = "test3";
      allowedUsers = ["test1"];
    };

    # Ensure that extra arguments are ignored by default

    # Ensure that extra arguments can be passed if explicitly allowed

    # Ensure that environment is empty by default

    # Ensure that specific environment variables can be passed

    # Ensure that LD_PRELOAD is always removed (should be done by ld.so.1 due to CAP_SETUID)

    #security.elewrap.ensure-no-args-passwd = {
    #  command = ["${pkgs.coreutils}/bin/id"];
    #  targetUser = "root";
    #  allowedUsers = ["test1"];
    #};

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

  # TODO ensure test1 can execute all
  # TODO test2 none
  # TODO root none
  # TODO ensure environment empty

  testScript = ''
    start_all()

    # wait for our service to start
    machine.wait_for_unit("multi-user.target")

    output = machine.succeed("runuser -u test1 /run/wrappers/bin/elewrap-id-as-root")
    assert output == "uid=0(root) gid=0(root) groups=0(root)\n"

    output = machine.succeed("runuser -u test1 /run/wrappers/bin/elewrap-id-as-test2")
    assert output == "uid=802(test2) gid=802(test2) groups=802(test2)\n"

    output = machine.succeed("runuser -u test1 /run/wrappers/bin/elewrap-id-as-test3")
    assert output == "uid=803(test3) gid=803(test3) groups=803(test3),901(group1),902(group2)\n"
  '';
}
