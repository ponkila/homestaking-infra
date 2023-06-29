{ pkgs, config, inputs, lib, ... }:

let
  # General
  infra.ip = "192.168.100.10";
  lighthouse.datadir = "/var/mnt/lighthouse";
  erigon.datadir = "/var/mnt/erigon";
  sshKeysPath = "/var/mnt/secrets/ssh/id_ed25519";
in
{
  homestakeros = {
    # Localization options
    localization = {
      hostname = "ponkila-ephemeral-beta";
      timezone = "Europe/Helsinki";
    };

    # User options
    user = {
      authorizedKeys = [
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAID5aw7sqJrXdKdNVu9IAyCCw1OYHXFQmFu/s/K+GAmGfAAAABHNzaDo= da@pusu"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINwWpZR5WuzyJlr7jYoe0mAYp+MJ12doozfqGz9/8NP/AAAABHNzaDo= da@pusu"
      ];
    };

    # SSH (system level) options
    ssh = {
      privateKeyFile = sshKeysPath;
    };

    # Erigon options
    erigon = {
      enable = true;
      endpoint = "http://${infra.ip}:8551";
      dataDir = erigon.datadir;
    };

    # Lighthouse options
    lighthouse = {
      enable = true;
      endpoint = "http://${infra.ip}:5052";
      dataDir = lighthouse.datadir;
      execEndpoint = "http://${infra.ip}:8551";
      mev-boost.endpoint = "http://${infra.ip}:18550";
      slasher = {
        enable = false;
        historyLength = 256;
        maxDatabaseSize = 16;
      };
    };

    # Mount options
    mounts = {
      # Secrets
      secrets = {
        enable = true;
        description = "secrets storage";

        what = "/dev/disk/by-label/secrets";
        where = "/var/mnt/secrets";
        options = "subvolid=256";
        type = "btrfs";

        before = [ "sshd.service" ];
        wantedBy = [ "multi-user.target" ];
      };
      # Erigon
      erigon = {
        enable = true;
        description = "erigon storage";

        what = "/dev/disk/by-label/erigon";
        where = erigon.datadir;
        options = "noatime";
        type = "btrfs";

        wantedBy = [ "multi-user.target" ];
      };
      # Lighthouse
      lighthouse = {
        enable = true;
        description = "lighthouse storage";

        what = "/dev/disk/by-label/lighthouse";
        where = lighthouse.datadir;
        options = "noatime";
        type = "btrfs";

        wantedBy = [ "multi-user.target" ];
      };
    };
  };

  # Secrets
  sops = {
    defaultSopsFile = ./secrets/default.yaml;
    secrets."wireguard/wg0" = {
      path = "%r/wireguard/wg0.conf";
    };
    age.sshKeyPaths = [ sshKeysPath ];
  };

  # Enable an ONC RPC directory service used by NFS
  services.rpcbind.enable = true;

  system.stateVersion = "23.05";
}
