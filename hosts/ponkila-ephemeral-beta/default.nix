{ pkgs, config, inputs, lib, ... }:

let
  # General
  infra.ip = "192.168.100.10";
  lighthouse.datadir = "/var/mnt/lighthouse";
  erigon.datadir = "/var/mnt/erigon";
  sshKeysPath = "/var/mnt/secrets/ssh/id_ed25519";
in
{
  fileSystems."/var/mnt/secrets" = lib.mkImageMediaOverride {
    fsType = "btrfs";
    device = "/dev/disk/by-label/erigon";
    options = [ "subvolid=256" ];
    neededForBoot = true;
  };

  homestakeros = {
    # Localization options
    localization = {
      hostname = "ponkila-ephemeral-beta";
      timezone = "Europe/Helsinki";
    };

    # SSH options
    ssh = {
      authorizedKeys = [
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAID5aw7sqJrXdKdNVu9IAyCCw1OYHXFQmFu/s/K+GAmGfAAAABHNzaDo= da@pusu"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINwWpZR5WuzyJlr7jYoe0mAYp+MJ12doozfqGz9/8NP/AAAABHNzaDo= da@pusu"
      ];
      privateKeyFile = sshKeysPath;
    };

    # Wireguard options
    vpn.wireguard = {
      enable = true;
      configFile = config.sops.secrets."wireguard/wg0".path;
    };

    # Erigon options
    execution.erigon = {
      enable = true;
      endpoint = "http://${infra.ip}:8551";
      dataDir = erigon.datadir;
      jwtSecretFile = "/var/mnt/erigon/jwt.hex";
    };

    # Lighthouse options
    consensus.lighthouse = {
      enable = true;
      endpoint = "http://${infra.ip}:5052";
      execEndpoint = "http://${infra.ip}:8551";
      dataDir = lighthouse.datadir;
      slasher = {
        enable = false;
        historyLength = 256;
        maxDatabaseSize = 16;
      };
      jwtSecretFile = "/var/mnt/lighthouse/jwt.hex";
    };

    # Addons
    addons.mev-boost = {
      enable = true;
      endpoint = "http://${infra.ip}:18550";
    };

    # Mount options
    mounts = {
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
    secrets."wireguard/wg0" = {
      sopsFile = ./secrets/default.yaml;
    };
    age.sshKeyPaths = [ sshKeysPath ];
  };

  # Enable an ONC RPC directory service used by NFS
  services.rpcbind.enable = true;

  system.stateVersion = "23.05";
}
