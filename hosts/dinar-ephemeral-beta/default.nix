{ pkgs, config, inputs, lib, ... }:

let
  # General
  infra.ip = "192.168.100.30";
  sshKeysPath = "/mnt/eth/secrets/ssh/id_ed25519";
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
  networking.hostName = "dinar-ephemeral-beta";
  time.timeZone = "Europe/Helsinki";

  boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.linux);

  # Erigon options
  erigon = rec {
    endpoint = infra.ip;
    datadir = "/mnt/eth/erigon";
  };

  # Lighthouse options
  lighthouse = rec {
    endpoint = infra.ip;
    datadir = "/mnt/eth/lighthouse";
    exec.endpoint = "http://${infra.ip}:8551";
    mev-boost.endpoint = "http://${infra.ip}:18550";
    slasher = {
      enable = false;
      history-length = 256;
      max-db-size = 16;
    };
  };

  home-manager.users = {
    root = { pkgs, ... }: {
      sops = {
        defaultSopsFile = ./secrets/default.yaml;
        secrets = {
          "wireguard/wg0" = {
            path = "%r/wireguard/wg0.conf";
          };
        };
        age.sshKeyPaths = [ sshKeysPath ];
      };
    };
    core = { pkgs, ... }: {
      sops = {
        defaultSopsFile = ./secrets/default.yaml;
        secrets = {
          "jwt.hex" = {
            path = "%r/jwt.hex";
          };
        };
        age.sshKeyPaths = [ sshKeysPath ];
      };
    };
  };

  systemd.mounts = [
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

  # SSH
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    hostKeys = [{
      path = sshKeysPath;
      type = "ed25519";
    }];
  };

  # Prometheus
  services.prometheus = {
    enable = false;
    port = 9001;
    exporters = {
      node = {
        enable = false;
        enabledCollectors = [ "systemd" ];
        port = 9002;
      };
    };
    scrapeConfigs = [
      {
        job_name = config.networking.hostName;
        static_configs = [{
          targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
        }];
      }
      {
        job_name = "erigon";
        metrics_path = "/debug/metrics/prometheus";
        scheme = "http";
        static_configs = [{
          targets = [ "127.0.0.1:6060" "127.0.0.1:6061" "127.0.0.1:6062" ];
        }];
      }
      {
        job_name = "lighthouse";
        scrape_interval = "5s";
        static_configs = [{
          targets = [ "127.0.0.1:5054" "127.0.0.1:5064" ];
        }];
      }
    ];
  };
  system.stateVersion = "23.05";
}