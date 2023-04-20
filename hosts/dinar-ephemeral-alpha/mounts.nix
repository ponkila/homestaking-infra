# sudo nix run github:nix-community/disko -- --mode zap_create_mount ./dinar-disko-config.nix --arg disks '[ "/dev/sda" ]'

{ disks ? [ "/dev/vdb" ], ... }: {
  disko.devices = {
    disk = {
      vdb = {
        device = builtins.elemAt disks 0;
        type = "disk";
        content = {
          type = "table";
          format = "gpt";
          partitions = [
            {
              name = "sda1";
              start = "1MiB";
              end = "10MiB";
              bootable = false;
              content = {
                type = "filesystem";
                format = "ext4";
                # systemd should handle mount
                #mountpoint = "/secrets";
              };
            }
            {
              name = "sda2";
              start = "10MiB";
              end = "50%";
              bootable = false;
              content = {
                type = "filesystem";
                format = "ext4";
                # systemd should handle mount
                #mountpoint = "/eth/lighthouse";
              };
            }
            {
              name = "sda3";
              start = "50%";
              end = "100%";
              bootable = false;
              content = {
                type = "filesystem";
                format = "ext4";
                # systemd should handle mount
                #mountpoint = "/eth/erigon";
              };
            }
          ];
        };
      };
    };
  };
}