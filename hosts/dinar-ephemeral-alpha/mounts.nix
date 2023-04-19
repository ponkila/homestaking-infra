{ disks ? [ "/dev/sda" ], ... }: {
  disko.devices = {
    disk = {
      sda = {
        type = "disk";
        device = builtins.elemAt disks 0;
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
                mountpoint = "/mnt/var/eth";
                mountOptions = [ "--label eth" ];
              };
            }
          ];
        };
      };
    };
  };
}