{ pkgs, config, inputs, lib, ... }:

let
  # General
  infra.ip = "192.168.100.10";
  lighthouse.datadir = "/var/mnt/lighthouse";
  erigon.datadir = "/var/mnt/erigon";
in
{
  # User options
  user = {
    authorizedKeys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAID5aw7sqJrXdKdNVu9IAyCCw1OYHXFQmFu/s/K+GAmGfAAAABHNzaDo= da@pusu"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINwWpZR5WuzyJlr7jYoe0mAYp+MJ12doozfqGz9/8NP/AAAABHNzaDo= da@pusu"
    ];
  };

  # Localization
  localization = {
    hostname = "ponkila-ephemeral-beta";
    timezone = "Europe/Helsinki";
    keymap = "us";
  };

  # Erigon options
  erigon = {
    endpoint = infra.ip;
    datadir = erigon.datadir;
  };

  # Lighthouse options
  lighthouse = {
    endpoint = infra.ip;
    datadir = lighthouse.datadir;
    exec.endpoint = "http://${infra.ip}:8551";
    mev-boost.endpoint = "http://${infra.ip}:18550";
    slasher = {
      enable = false;
      history-length = 256;
      max-db-size = 16;
    };
  };

  # Mev-boost
  mev-boost = {
    enable = true;
  };

  # SSH
  ssh = {
    privateKeyPath = "/var/mnt/secrets/ssh/id_ed25519";
  };

  mounts = [
    # Secrets
    {
      description = "secrets storage";

      what = "/dev/disk/by-label/secrets";
      where = "/var/mnt/secrets";
      type = "btrfs";

      before = [ "sshd.service" ];
      wantedBy = [ "multi-user.target" ];
    }
    # Erigon
    {
      description = "erigon storage";

      what = "/dev/disk/by-label/erigon";
      where = self.options.erigon.datadir;
      options = "noatime";
      type = "btrfs";

      wantedBy = [ "multi-user.target" ];
    }
    # Lighthouse
    {
      description = "lighthouse storage";

      what = "/dev/disk/by-label/lighthouse";
      where = self.options.lighthouse.datadir;
      options = "noatime";
      type = "btrfs";

      wantedBy = [ "multi-user.target" ];
    }
  ];
}
