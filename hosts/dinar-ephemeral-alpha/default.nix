{ pkgs, config, inputs, lib, ... }:

let
  # General
  infra.ip = "192.168.100.31";
  lighthouse.datadir = "/mnt/eth/lighthouse";
  erigon.datadir = "/mnt/eth/erigon";
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

  # Localization options
  localization = {
    hostname = "dinar-ephemeral-alpha";
    timezone = "Europe/Helsinki";
    keymap = "fi";
  };

  # Erigon options
  erigon = {
    enable = true;
    endpoint = infra.ip;
    datadir = erigon.datadir;
  };

  # Lighthouse options
  lighthouse = {
    enable = true;
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

  # MEV-Boost options
  mev-boost = {
    enable = true;
  };

  # SSH (system level) options
  ssh = {
    privateKeyPath = "/var/mnt/secrets/ssh/id_ed25519";
  };

  # Mounts
  mounts = [
    {
      enable = true;
      description = "storage";

      what = "/dev/sda1";
      where = "/mnt/eth";
      type = "ext4";

      before = [ "sops-nix.service" "sshd.service" ];
      wantedBy = [ "multi-user.target" ];
    }
  ];
  system.stateVersion = "23.05";
}
