{ pkgs, config, inputs, lib, ... }:

let
  # General
  infra.ip = "192.168.100.10";
in
{
  # User options
  user = {
    name = "core"; # needs to be configured in /home-manager/<name>/default.nix
    shell = "fish";
    authorizedKeys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAID5aw7sqJrXdKdNVu9IAyCCw1OYHXFQmFu/s/K+GAmGfAAAABHNzaDo= da@pusu"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINwWpZR5WuzyJlr7jYoe0mAYp+MJ12doozfqGz9/8NP/AAAABHNzaDo= da@pusu"
    ];
  };

  # Erigon options
  erigon = rec {
    endpoint = infra.ip;
    datadir = "/var/mnt/erigon";
    mount = {
      source = "/dev/disk/by-label/erigon";
      target = datadir;
    };
  };

  # Lighthouse options
  lighthouse = rec {
    endpoint = infra.ip;
    datadir = "/var/mnt/lighthouse";
    exec.endpoint = "http://${infra.ip}:8551";
    mev-boost.endpoint = "http://${infra.ip}:18550";
    mount = {
      source = "/dev/disk/by-label/lighthouse";
      target = datadir;
    };
  };

  # Localization
  networking.hostName = "ponkila-ephemeral-beta";
  time.timeZone = "Europe/Helsinki";

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
  ];

  ## Allow passwordless sudo from wheel group
  security.sudo = {
    enable = lib.mkDefault true;
    wheelNeedsPassword = lib.mkForce false;
  };
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    hostKeys = [{
      path = "/var/mnt/secrets/ssh/id_ed25519";
      type = "ed25519";
    }];
  };

  services.timesyncd.enable = false;
  services.chrony = {
    enable = true;
    servers = [
      "ntp1.hetzner.de"
      "ntp2.hetzner.com"
      "ntp3.hetzner.net"
    ];
  };

  networking.firewall = {
    allowedTCPPorts = [ 30303 30304 42069 9000 ];
    allowedUDPPorts = [ 30303 30304 42069 9000 ];
  };

  systemd.watchdog.device = "/dev/watchdog";
  systemd.watchdog.runtimeTime = "30s";

  systemd.mounts = [
    {
      enable = true;

      description = "secrets storage";

      what = "/dev/disk/by-label/secrets";
      where = "/var/mnt/secrets";
      type = "btrfs";

      before = [ "sops-nix.service" "sshd.service" ];
      wantedBy = [ "multi-user.target" ];
    }
  ];

  systemd.services.wg0 = {
    enable = true;

    description = "wireguard interface for cross-node communication";
    requires = [ "network-online.target" ];
    after = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
    };

    script = ''${pkgs.wireguard-tools}/bin/wg-quick \
      up /run/user/1000/wireguard/wg0.conf
    '';

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.linger = {
    enable = true;

    requires = [ "local-fs.target" ];
    after = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        /run/current-system/sw/bin/loginctl enable-linger core
      '';
    };

    wantedBy = [ "multi-user.target" ];
  };

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
