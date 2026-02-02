{ pkgs
, config
, lib
, outputs
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
  fileSystems."/var/mnt/secrets" = lib.mkImageMediaOverride {
    fsType = "btrfs";
    device = "/dev/sda";
    options = [ "subvolid=256" ];
    neededForBoot = true;
  };

  environment.systemPackages = [ pkgs.wireguard-tools ];
  services.caddy = {
    enable = true;
    globalConfig = ''
      auto_https off
      servers {
        metrics
      }
    '';
    extraConfig = ''
      http://192.168.100.40:8545 {

        log {
          output stdout
          format json
        }

        reverse_proxy {
          to localhost:8547 192.168.100.50:8546
          lb_policy first

          health_interval 10s
          health_timeout 5s

          fail_duration 30s
          unhealthy_latency 300ms
        }
      }
    '';
  };

  services.chrony = {
    enable = true;
    servers = [
      "time.cloudflare.com"
      "ntp1.hetzner.de"
      "time.mikes.fi"
    ];
  };

  virtualisation = {
    podman.enable = true;
    oci-containers.containers = {
      keep-core = {
        image = "localhost/keep-core/v2.4.1:latest";
        environmentFiles = [
          config.sops.secrets."keep-network/env".path
        ];
        extraOptions = [
          "--network=host"
        ];
        environment = {
          GOLOG_LOG_FMT = "json";
        };
        pull = "never";
        user = "1000:1000";
        volumes = [
          "/var/mnt/keep-network:/var/mnt/keep-network"
          "/run/secrets/keep-network/operator-key:/run/secrets/keep-network/operator-key"
        ];
        cmd = [
          "start"
          "--ethereum.url"
          "ws://192.168.100.40:8545"
          "--ethereum.keyFile"
          "/run/secrets/keep-network/operator-key"
          "--bitcoin.electrum.url"
          "tcp://192.168.100.40:50001"
          "--storage.dir"
          "/var/mnt/keep-network"
        ];
      };
    };
  };

  systemd.services.keep-network = {
    enable = false;

    description = "keep-network bridge service";
    requires = [ "caddy.service" "nginx.service" ];
    after = [ "caddy.service" "nginx.service" ];
    environment = {
      GOLOG_LOG_FMT = "json";
    };

    serviceConfig = {
      EnvironmentFile = ''${config.sops.secrets."keep-network/env".path}'';
      Restart = "always";
      RestartSec = "5s";
      User = "core";
      Group = "core";
      Type = "simple";
    };

    script = ''/var/mnt/keep-network/v2.4.1/keep-client start \
      --ethereum.url ws://192.168.100.40:8545 \
      --ethereum.keyFile /run/secrets/keep-network/operator-key \
      --bitcoin.electrum.url tcp://192.168.100.40:50001 \
      --storage.dir /var/mnt/keep-network
    '';

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.mitmproxy-ponkila = {

    enable = true;
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
      Type = "simple";
    };

    script = ''${pkgs.mitmproxy}/bin/mitmdump \
      --mode reverse:http://192.168.100.10:8546 \
      --listen-port 8547 \
      --set websocket=true \
      --set flow_detail=3 \
      -w /var/log/mitmproxy/ponkila.log
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
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIOdsfK46X5IhxxEy81am6A8YnHo2rcF2qZ75cHOKG7ToAAAACHNzaDprYXJp ssh:kari"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAILn/9IHTGC1sLxnPnLbtJpvF7HgXQ8xNkRwSLq8ay8eJAAAADHNzaDpzdGFybGFicw== ssh:starlabs"
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
      etcd = {
        enable = true;

        what = "/dev/sda";
        where = "/var/mnt/etcd";
        type = "btrfs";
        options = "subvolid=260";

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
            Gateway = "fe80::1";
          }
        ];
      };
      "50-simple" = {
        dns = [ "127.0.0.1:1053" ];
        domains = [ "ponkila.nix" ];
      };
    };
  };
  networking = {
    firewall = {
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
    nameservers = [ "localhost:1053" ];
    useDHCP = false;
  };

  # Hetzner console access
  services.getty.autologinUser = "core";

  imports = [
    ../../nixosModules/mesh.nix
    ../../nixosModules/monitoring.nix
  ];

  mesh = {
    enable = true;
    endpoint = {
      ip = "hetzner-ephemeral-alpha.ponkila.com";
      port = 51820;
    };
    etcd = {
      enable = true;
      dataDir = "/var/mnt/etcd";
      openFirewall = true;
    };
  };

  monitoring = {
    enable = true;
    grafana = {
      enable = true;
      address = "192.168.100.40";
    };
    logs = true;
    traces = false;
    alerts = true;
  };

  services.prometheus = let fixpoint = config.services.prometheus.exporters; in rec  {
    enable = true;
    alertmanager = {
      enable = true;
      configuration = {
        route = {
          receiver = "telegram";
        };
        receivers = [
          {
            name = "telegram";
            telegram_configs = [{
              send_resolved = true;
              bot_token_file = "/var/mnt/secrets/telegram.txt";
              chat_id = -1003849721555;
            }];
          }
        ];
      };
    };
    exporters = {
      cgroup.enable = true;
    };
    scrapeConfigs =
      let
        port = n: toString fixpoint.${n}.port;
        srapeConfigs' = lib.mapAttrsToList
          (job_name: _: {
            inherit job_name;
            static_configs = [{ targets = [ "localhost:${port job_name}" ]; }];
          })
          exporters; # <- exporters defined above
      in
      srapeConfigs' ++ [
        {
          job_name = "keep-core";
          static_configs = [{ targets = [ "127.0.0.1:9601" ]; }];
        }
        {
          job_name = "caddy";
          static_configs = [{ targets = [ "127.0.0.1:2019" ]; }];
        }
      ];
    ruleFiles = [
      "${outputs.packages.x86_64-linux.awesome-prometheus-alerts.outPath}/caddy/embedded-exporter.yml"
    ];
  };

  services.grafana.provision.dashboards.settings.providers = [{
    name = "default";
    options.path = pkgs.linkFarm "grafana-dashboards" [
      { name = "tbtc.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-tbtc; }
      { name = "cgroup.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-cgroup; }
    ];
  }];

  system.stateVersion = "25.05";
}
