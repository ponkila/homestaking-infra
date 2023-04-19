# sudo nix run github:nix-community/disko -- --mode zap_create_mount ./dinar-disko-config.nix 

{
  disko.devices = {
    disk.sda = {
      device = "/dev/sda";
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
              mountpoint = "/var/mnt/eth";
              mountOptions = [ "--label eth" ];
            };
          }
        ];
      };
    };
  };
}