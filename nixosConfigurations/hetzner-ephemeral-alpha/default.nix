{
  pkgs,
  config,
  inputs,
  outputs,
  lib,
  ...
}: let
  # General
  sshKeysPath = "/var/mnt/secrets/ssh/id_ed25519";
  ponkila-ephemeral-beta = outputs.nixosConfigurations.ponkila-ephemeral-beta.config.homestakeros;
in {
  boot.initrd.availableKernelModules = [
    "virtio"
    "virtio_rng"
    "virtio_console"
    "virtio_balloon"
    "virtio_scsi"
    "virtio_gpu"
    "virtio_pci"
    "virtio_net"

    "dm_mod"
    "btrfs"
  ];
  # Workaround for https://github.com/Mic92/sops-nix/issues/24
  fileSystems."/var/mnt/secrets" = lib.mkImageMediaOverride {
    fsType = "btrfs";
    device = "/dev/sda";
    options = ["subvolid=256"];
    neededForBoot = true;
  };

  environment.systemPackages = with pkgs; [
    keep-core
  ];

  environment.etc."Caddyfile" = {
    text = ''
       {
        auto_https off
        servers {
          metrics
        }
        debug True
      }

      http://192.168.100.40:8545 {

        reverse_proxy {
          to 192.168.100.10:8545 192.168.100.21:8545 192.168.100.30:8545 192.168.100.31:8545

          health_uri /eth/v1/node/syncing
          health_port 5052
          health_interval 11s
          health_body `"is_syncing":false,"is_optimistic":false,"el_offline":false`

          fail_duration 30s
          unhealthy_latency 300ms
        }
      }
    '';
  };
  services.caddy = {
    enable = true;
    configFile = "/etc/Caddyfile";
  };

  systemd.services.keep-network = {
    enable = true;

    description = "keep-network bridge service";
    requires = ["caddy.service" "nginx.service"];
    after = ["caddy.service" "nginx.service"];

    serviceConfig = {
      EnvironmentFile = ''${config.sops.secrets."keep-network/env".path}'';
      Restart = "always";
      RestartSec = "5s";
      User = "core";
      Group = "core";
      Type = "simple";
    };

    script = ''      /var/mnt/keep-core/keep-client \
            start \
            --ethereum.url ws://192.168.100.40:8545 \
            --ethereum.keyFile /run/secrets/keep-network/operator-key \
            --bitcoin.electrum.url tcp://192.168.100.40:50001 \
            --storage.dir /var/mnt/keep-network
    '';

    wantedBy = ["multi-user.target"];
  };

  services.nginx = {
    enable = true;
    config = ''
      events {
        worker_connections 1024;
      }

      http {
        server {
          listen 8080;
          location = /healthz {
            stub_status;
          }
        }
      }

      stream {

        upstream bitcoin {
          server 192.168.100.10:50001;
          server 192.168.100.31:50001;
        }

        server {
          listen 192.168.100.40:50001;
          proxy_pass bitcoin;
        }

      }
    '';
  };
  systemd.services.nginx.requires = ["wg-quick-wg0.service"];
  systemd.services.nginx.after = ["wg-quick-wg0.service"];

  homestakeros = {
    # Localization options
    localization = {
      hostname = "hetzner-ephemeral-alpha";
      timezone = "Europe/Helsinki";
    };

    # SSH options
    ssh = {
      authorizedKeys = [
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAID5aw7sqJrXdKdNVu9IAyCCw1OYHXFQmFu/s/K+GAmGfAAAABHNzaDo= da@pusu"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINwWpZR5WuzyJlr7jYoe0mAYp+MJ12doozfqGz9/8NP/AAAABHNzaDo= da@pusu"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCkfHIgiK8S5awFn+oOdduS2mp5UGT4ki/ndoMArBol1dvRSKAdHS4okCX/umiy4BqAsDFkpYWuwe897NdOosba0iVyrFsYRou9FrOnQIMRIgtAvaOXeo2U4432glzH4WsMD+D+F4wHZ7walsrkaIPihpoHtWp8DkTPcFm1D8GP1o5TNpTjSFSuPFSzC2nburVcyfxZJluh/hxnxtYLNrmwOOHLhXcTmy5rQQ5u2HI5y64tS6fnKxxozA2gPaVro5+W5e3WtpSDGdd2NkPDzrMMmwYFEv4Tw9ooUfaJhXhq7AJakK/nTfpLquL9XSia8af+aOzx/p1v25f56dESlhNzcSlREP52hTA9T3foCA2IBkDitBeeGhUeeerQdczoRFxxSjoI244bPwAZ+tKIwO0XFaxLyd3jjzlya0F9w1N7wN0ZO4hY1NVv7oaYTUcU7TnvqGEMGLZpQBnIn7DCrUjKeW4AIUGvxcCP+F16lqFkuLSCgOAHM59NECVwBAOPGDk="
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJdbU8l66hVUAqk900GmEme5uhWcs05JMUQv2eD0j7MI juuso@starlabs"
      ];
      privateKeyFile = sshKeysPath;
    };

    # Wireguard options
    vpn.wireguard = {
      enable = true;
      configFile = config.sops.secrets."wireguard/wg0".path;
    };

    mounts = {
      blutgang = {
        enable = true;
        description = "blutgang store";

        what = "/dev/sda";
        where = "/var/mnt/blutgang";
        type = "btrfs";
        options = "subvolid=257";

        wantedBy = ["multi-user.target"];
      };
      keep-network = {
        enable = true;
        description = "keep-network store";

        what = "/dev/sda";
        where = "/var/mnt/keep-network";
        type = "btrfs";
        options = "subvolid=258";

        wantedBy = ["multi-user.target"];
      };
    };
  };

  # Secrets
  sops = {
    defaultSopsFile = ./secrets/default.yaml;
    secrets."wireguard/wg0" = {};
    secrets."keep-network/env" = {
      owner = "core";
      group = "core";
    };
    secrets."keep-network/operator-key" = {
      owner = "core";
      group = "core";
    };
    secrets."netdata/health_alarm_notify.conf" = {
      owner = "netdata";
      group = "netdata";
    };
    age.sshKeyPaths = [sshKeysPath];
  };

  networking.firewall = {
    allowedTCPPorts = [
      # https://docs.threshold.network/staking-and-running-a-node/tbtc-v2-node-setup/network-configuration
      3919
      9601
    ];
    interfaces."wg0" = {
      allowedTCPPorts = [
        8545 # eth rpc: ws or http
        50001 # bitcoin electrum rpc
      ];
      allowedUDPPorts = [
        8545
        50001
      ];
    };
  };

  services.netdata = {
    enable = true;
    configDir = {
      "health_alarm_notify.conf" = config.sops.secrets."netdata/health_alarm_notify.conf".path;
      "go.d/prometheus.conf" = pkgs.writeText "go.d/prometheus.conf" ''
        jobs:
        - name: keep-core
          url: http://127.0.0.1:9601/metrics
        - name: caddy
          url: http://127.0.0.1:2019/metrics
      '';
      "health.d/btc_connectivity.conf" = pkgs.writeText "health.d/btc_connectivity.conf" ''
         alarm: juuso: btc_connectivity
            on: prometheus_keep-core.btc_connectivity
        lookup: min -10s
         every: 10s
          crit: $this == 0
      '';
      "health.d/eth_connectivity.conf" = pkgs.writeText "health.d/eth_connectivity.conf" ''
         alarm: juuso: eth_connectivity
        lookup: min -10s
            on: prometheus_keep-core.eth_connectivity
         every: 10s
          crit: $this == 0
      '';
      "health.d/upstream_192.168.100.10.conf" = pkgs.writeText "health.d/upstream_192.168.100.10.conf" ''
         alarm: juuso: healthy-upstream_192.168.100.10
        lookup: min -10s
            on: prometheus_caddy.caddy_reverse_proxy_upstreams_healthy-upstream_192.168.100.10_8545
         every: 10s
          warn: $this == 0
      '';
      "health.d/upstream_192.168.100.21.conf" = pkgs.writeText "health.d/upstream_192.168.100.21.conf" ''
         alarm: tommi: healthy-upstream_192.168.100.21
        lookup: min -10s
            on: prometheus_caddy.caddy_reverse_proxy_upstreams_healthy-upstream_192.168.100.21_8545
         every: 10s
          warn: $this == 0
      '';
      "health.d/upstream_192.168.100.30.conf" = pkgs.writeText "health.d/upstream_192.168.100.30.conf" ''
         alarm: tommi: healthy-upstream_192.168.100.30
        lookup: min -10s
            on: prometheus_caddy.caddy_reverse_proxy_upstreams_healthy-upstream_192.168.100.30_8545
         every: 10s
          warn: $this == 0
      '';
      "health.d/upstream_192.168.100.31.conf" = pkgs.writeText "health.d/upstream_192.168.100.31.conf" ''
         alarm: tommi: healthy-upstream_192.168.100.31
        lookup: min -10s
            on: prometheus_caddy.caddy_reverse_proxy_upstreams_healthy-upstream_192.168.100.31_8545
         every: 10s
          warn: $this == 0
      '';
    };
  };

  system.stateVersion = "23.05";
}
