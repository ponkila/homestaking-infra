{ pkgs
, config
, lib
, ...
}:
let
  # General
  sshKeysPath = "/var/mnt/secrets/ssh/id_ed25519";
in
{
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
    options = [ "subvolid=256" ];
    neededForBoot = true;
  };

  environment.systemPackages = [ pkgs.wireguard-tools ];
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
          to 192.168.100.10:8546 192.168.100.33:8546

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
    requires = [ "caddy.service" "nginx.service" ];
    after = [ "caddy.service" "nginx.service" ];

    serviceConfig = {
      EnvironmentFile = ''${config.sops.secrets."keep-network/env".path}'';
      Restart = "always";
      RestartSec = "5s";
      User = "core";
      Group = "core";
      Type = "simple";
    };

    script = ''/var/mnt/keep-network/v2.1.0/keep-client start \
      --ethereum.url ws://192.168.100.40:8545 \
      --ethereum.keyFile /run/secrets/keep-network/operator-key \
      --bitcoin.electrum.url tcp://192.168.100.40:50001 \
      --storage.dir /var/mnt/keep-network
    '';

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.ssv-dkg-holesky = {
    enable = false;

    description = "ssv-dkg holesky";

    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };

    script = ''nix run github:jhvst/nix-community/jhvst/ssv-dkg#ssv-dkg -- start-operator \
      --privKey /var/mnt/ssv-dkg/privateKey \
      --privKeyPassword /var/mnt/ssv-dkg/password \
      --operatorID 881 \
      --port 3030 \
      --logLevel info \
      --logFormat json \
      --logLevelFormat capitalColor \
      --logFilePath /var/mnt/ssv-dkg/debug.log \
      --outputPath /var/mnt/ssv-dkg \
      --serverTLSCertPath /var/mnt/ssv-dkg/tls.crt \
      --serverTLSKeyPath /var/mnt/ssv-dkg/tls.key
    '';

    wantedBy = [ "multi-user.target" ];
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
          server 192.168.100.50:50001;
        }

        server {
          listen 192.168.100.40:50001;
          proxy_pass bitcoin;
        }

      }
    '';
  };
  systemd.services.nginx.requires = [ "wg-quick-wg0.service" ];
  systemd.services.nginx.after = [ "wg-quick-wg0.service" ];

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
      keep-network = {
        enable = true;
        description = "keep-network store";

        what = "/dev/sda";
        where = "/var/mnt/keep-network";
        type = "btrfs";
        options = "subvolid=258";

        wantedBy = [ "multi-user.target" ];
      };
      ssv-dkg = {
        enable = true;

        what = "/dev/sda";
        where = "/var/mnt/ssv-dkg";
        type = "btrfs";
        options = "subvolid=259";

        wantedBy = [ "multi-user.target" ];
      };
    };
  };

  # Secrets
  age = {
    rekey = {
      agePlugins = [ pkgs.age-plugin-fido2-hmac ];
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKfkQ9dHiYK8LUsjM06dHKI1z/Gh7IiG0rUH3sxj4Stc";
    };
  };
  sops = {
    defaultSopsFile = ./secrets/default.yaml;
    secrets."wireguard/wg0" = { };
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
    secrets."holesky/ssvnode/password" = { };
    secrets."holesky/ssvnode/privateKey" = { };
    secrets."holesky/ssvnode/publicKey" = { };
    age.sshKeyPaths = [ sshKeysPath ];
  };

  systemd.network = {
    enable = true;
    networks = {
      "10-wan" = {
        address = [ "2a01:4f9:c011:a71d::1/64" ];
        linkConfig.RequiredForOnline = "routable";
        matchConfig.Name = "enp1s0";
        networkConfig = {
          DHCP = "ipv4";
        };
        routes = [
          {
            routeConfig.Gateway = "fe80::1";
          }
        ];
      };
    };
  };
  networking = {
    firewall = {
      allowedTCPPorts = [
        # https://docs.threshold.network/staking-and-running-a-node/tbtc-v2-node-setup/network-configuration
        3919
        9601
        # https://docs.ssv.network/operator-user-guides/operator-node/enabling-dkg
        3030
      ];
      allowedUDPPorts = [
        51820
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
    useDHCP = false;
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
        on: prometheus_caddy.caddy_reverse_proxy_upstreams_healthy-upstream_192.168.100.10_8546
        every: 10s
        warn: $this == 0
      '';
      "health.d/upstream_192.168.100.33.conf" = pkgs.writeText "health.d/upstream_192.168.100.33.conf" ''
        alarm: tommi: healthy-upstream_192.168.100.33
        lookup: min -10s
        on: prometheus_caddy.caddy_reverse_proxy_upstreams_healthy-upstream_192.168.100.33_8546
        every: 10s
        warn: $this == 0
      '';
    };
  };

  # Hetzner console access
  services.getty.autologinUser = "core";

  wirenix = {
    enable = true;
    peerName = "node1"; # defaults to hostname otherwise
    configurer = "networkd"; # defaults to "static", could also be "networkd"
    keyProviders = [ "agenix-rekey" ]; # could also be ["agenix-rekey"] or ["acl" "agenix-rekey"]
    secretsDir = ../../nixosModules/wirenix/agenix; # only if you're using agenix-rekey
    aclConfig = import ../../nixosModules/wirenix/acl.nix;
  };

  system.stateVersion = "24.05";
}

