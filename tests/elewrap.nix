(import ./lib.nix) {
  name = "elewrap-nixos";
  nodes.machine = {
    self,
    pkgs,
    ...
  }: {
    imports = [self.nixosModules.default];
    nixpkgs.overlays = [self.overlays.default];

    security.elewrap.id-as-root = {
      command = ["${pkgs.coreutils}/bin/id"];
      targetUser = "root";
      allowedUsers = ["test1"];
    };

    security.elewrap.id-as-test2 = {
      command = ["${pkgs.coreutils}/bin/id"];
      targetUser = "test2";
      allowedUsers = ["test1"];
    };

    security.elewrap.id-as-test3 = {
      command = ["${pkgs.coreutils}/bin/id"];
      targetUser = "test3";
      allowedUsers = ["test1"];
    };

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
    import sys
    print(output, file=sys.stderr)
    assert output == "uid=802(test2) gid=802(test2) groups=802(test2)\n"

    output = machine.succeed("runuser -u test1 /run/wrappers/bin/elewrap-id-as-test3")
    assert output == "uid=803(test3) gid=803(test3) groups=902(group2),901(group1),803(test3)\n"
  '';
}
