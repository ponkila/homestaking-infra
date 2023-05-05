{ pkgs, config, inputs, lib, ... }:
{
  # User options
  users = {
    juuso.authorizedKeys = [ "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local" ];
    kari.authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque" ];
  };

  # Users group
  users.groups.users = {};

  # Localization
  networking.hostName = "hetzner-ephemeral-alpha";
  time.timeZone = "Europe/Helsinki";

  services.hercules-ci-agent = {
    enable = true;
    settings.baseDirectory = "/var/mnt/nvme/hercules-ci-agent";
  };

  boot.initrd.availableKernelModules = [ "btrfs" ];
  fileSystems."/nix/.rw-store" = lib.mkImageMediaOverride {
    fsType = "btrfs";
    device = "/dev/disk/by-label/nvme";
    options = [ "compress=zstd:2,noatime,subvolid=258" ];
    neededForBoot = true;
  };

  systemd.mounts = [
    {
      enable = true;

      description = "persistent nvme storage";

      what = "/dev/disk/by-label/nvme";
      where = "/var/mnt/nvme";
      type = "btrfs";
      options = "noatime";

      wantedBy = [ "multi-user.target" ];
    }
  ];

  # SSH
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  system.stateVersion = "23.05";
}
