{ pkgs, config, inputs, lib, ... }:

let
  # General
  infra.ip = "192.168.100.30";
  sshKeysPath = "/mnt/eth/secrets/ssh/id_ed25519";
in
{
  # Use stable kernel
  boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.linux);

  homestakeros = {
    # Localization options
    localization = {
      hostname = "dinar-ephemeral-beta";
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
      dataDir = "/mnt/eth/erigon";
    };

    # Lighthouse options
    lighthouse = {
      enable = true;
      endpoint = "http://${infra.ip}:5052";
      dataDir = "/mnt/eth/lighthouse";
      execEndpoint = "http://${infra.ip}:8551";
      mev-boost.endpoint = "http://${infra.ip}:18550";
      slasher = {
        enable = false;
        historyLength = 256;
        maxDatabaseSize = 16;
      };
    };

    # Mounts
    mounts.eth = {
      enable = true;
      description = "storage";

      what = "/dev/sda1";
      where = "/mnt/eth";
      type = "ext4";

      before = [ "sops-nix.service" "sshd.service" ];
      wantedBy = [ "multi-user.target" ];
    };
  };

  # Secrets
  sops = {
    defaultSopsFile = ./secrets/default.yaml;
    secrets = {
      "wireguard/wg0" = {
        path = "%r/wireguard/wg0.conf";
      };
      "jwt.hex" = {
        path = "%r/jwt.hex";
      };
    };
    age.sshKeyPaths = [ sshKeysPath ];
  };

  system.stateVersion = "23.05";
}
