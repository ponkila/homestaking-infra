# sudo nix run github:nix-community/disko -- --mode zap_create_mount ./mounts.nix --arg disks '[ "/dev/sda" ]'

{ disks ? [ "/dev/sda" ], ... }: {
  disko.devices = {
    disk = {
      disk0 = {
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
              bootable = false;
              content = {
                type = "filesystem";
                format = "ext4";
                # mountpoint has invisible /mnt prefix 
                mountpoint = "/eth";
              };
            }
          ];
        };
      };
    };
  };
}
