{ pkgs, config, inputs, lib, ... }:

let
  # General
  infra.ip = "192.168.100.31";
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

  # Localization options
  localization = {
    hostname = "dinar-ephemeral-alpha";
    timezone = "Europe/Helsinki";
  };

  # Erigon options
  erigon = {
    enable = true;
    endpoint = infra.ip;
    datadir = "/mnt/eth/erigon";
  };

  # Lighthouse options
  lighthouse = {
    enable = true;
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

  # SSH
  services.openssh = {
    enable = true;
    hostKeys = [{
      path = sshKeysPath;
      type = "ed25519";
    }];
    allowSFTP = false;
    extraConfig = ''
      AllowTcpForwarding yes
      X11Forwarding no
      AllowAgentForwarding no
      AllowStreamLocalForwarding no
      AuthenticationMethods publickey
    '';
    settings.PasswordAuthentication = false;
    settings.challengeResponseAuthentication = false;
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
