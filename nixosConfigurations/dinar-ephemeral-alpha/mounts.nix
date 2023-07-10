# sudo nix run github:nix-community/disko -- --mode zap_create_mount ./mounts.nix --arg disks '[ "/dev/sda" ]'

{ disks ? [ "/dev/sda" ], ... }: {
  disko.devices = {
    disk = {
      sda = {
        device = builtins.elemAt disks 0;
        type = "disk";
        content = {
          type = "table";
          format = "gpt";
          partitions = [
            {
              name = "sda1";
              start = "1MiB";
              end = "100%";
              part-type = "primary";
              bootable = false;
              content = {
                type = "filesystem";
                format = "ext4";
                # mountpoint has invisible /mnt prefix 
                # systemd should handle mount
                #mountpoint = "/eth";
              };
            }
          ];
        };
      };
    };
  };
}
