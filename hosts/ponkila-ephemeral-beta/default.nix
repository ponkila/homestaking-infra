{ pkgs, config, inputs, lib, ... }:

let
  # General
  infra.ip = "192.168.100.10";
in
{
  imports = [
    ../../system/global.nix
    ../../modules/eth/lighthouse.nix
    ../../modules/eth/mev-boost.nix
    ../../modules/eth/erigon.nix
  ];

  # Erigon options
  erigon_cfg = rec {
    endpoint = infra.ip;
    datadir = "/var/mnt/erigon";
    mount = {
      source = "/dev/disk/by-label/erigon";
      target = "/var/mnt/erigon";
    };
  };

  # Lighthouse options
  lighthouse_cfg = rec {
    endpoint = infra.ip;
    exec.endpoint = infra.ip;
    mev-boost.endpoint = infra.ip;
    datadir = "/var/mnt/lighthouse";
    mount = {
      source = "/dev/disk/by-label/lighthouse";
      target = "/var/mnt/lighthouse";
    };
  };

  # Localization
  networking.hostName = "ponkila-ephemeral-beta";
  time.timeZone = "Europe/Helsinki";

  home-manager.users.core = { pkgs, ... }: {

    sops = {
      defaultSopsFile = ./secrets/default.yaml;
      secrets."wireguard/wg0" = {
        path = "%r/wireguard/wg0.conf";
      };
      age.sshKeyPaths = [ "/var/mnt/secrets/ssh/id_ed25519" ];
    };

    home.packages = with pkgs; [
      file
      tree
      bind # nslookup
    ];

    programs = {
      tmux.enable = true;
      htop.enable = true;
      vim.enable = true;
      git.enable = true;
      fish.enable = true;
      fish.loginShellInit = "fish_add_path --move --prepend --path $HOME/.nix-profile/bin /run/wrappers/bin /etc/profiles/per-user/$USER/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin";

      home-manager.enable = true;
    };

    home.stateVersion = "23.05";
  };

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
  ];

  ## Allow passwordless sudo from nixos user
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
