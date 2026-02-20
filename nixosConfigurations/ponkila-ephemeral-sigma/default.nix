{ pkgs
, lib
, config
, outputs
, ...
}:
{
  boot.initrd.availableKernelModules = [
    "dm_mod"
    "btrfs"
  ];
  fileSystems."/etc/ssh" = lib.mkImageMediaOverride {
    fsType = "btrfs";
    device = "/dev/disk/by-label/nvme";
    options = [ "subvolid=256" ];
    neededForBoot = true;
  };

  homestakeros = {
    # Localization options
    localization = {
      hostname = "ponkila-ephemeral-sigma";
      timezone = "Europe/Helsinki";
    };

    # SSH options
    ssh = {
      authorizedKeys = [
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAILn/9IHTGC1sLxnPnLbtJpvF7HgXQ8xNkRwSLq8ay8eJAAAADHNzaDpzdGFybGFicw== ssh:starlabs"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIJuPW2qxz9ZvzcaO5RzcDr99t55PUBjmYC9ADX6sJhbjAAAABHNzaDo= ssh:muro"
      ];
      privateKeyFile = "/etc/ssh/ssh_host_ed25519_key";
    };

    vpn.wireguard = {
      enable = true;
      configFile = "/etc/wireguard/dinar.conf";
    };

    mounts = {
      wireguard = {
        enable = true;
        description = "wireguard storage";

        what = "/dev/disk/by-label/nvme";
        where = "/etc/wireguard";
        type = "btrfs";
        options = "subvolid=257";

        before = [ "wg-quick-dinar.service" ];
        wantedBy = [ "multi-user.target" ];
      };
    };
  };

  systemd.network = {
    enable = true;
    networks = {
      "10-wan" = {
        linkConfig.RequiredForOnline = "routable";
        matchConfig.Name = "enp1s0";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
          IPv6PrivacyExtensions = "prefer-public";
        };
        dhcpV6Config = {
          DUIDType = "link-layer";
        };
        dns = [ "127.0.0.1:1053" ];
        address = [ "192.168.1.20/24" ]; # static IP
      };
    };
  };
  networking = {
    firewall.interfaces."enp1s0".allowedTCPPorts = [
      9101 # IPv6 resolver for router
    ];
    nameservers = [ "127.0.0.1:1053" ];
    useDHCP = false;
  };

  imports = [
    ../../nixosModules/mesh.nix
    ../../nixosModules/monitoring.nix
  ];
  mesh = {
    enable = true;
    endpoint = {
      ip = "alb17.ponkila.com";
      port = 51820;
    };
  };
  monitoring = {
    enable = true;
    grafana = {
      enable = true;
      address = "0.0.0.0";
    };
    logs = true;
    alerts = true;
  };

  environment.systemPackages = with pkgs; [
    lighthouse
  ];

  services.chrony = {
    enable = true;
    servers = [
      "time.cloudflare.com"
      "ntp1.hetzner.de"
      "time.mikes.fi"
    ];
  };

  containers.lighthouse = {
    privateNetwork = false;
    config = _: {

      environment.systemPackages = with pkgs; [
        lighthouse
        curl
      ];

      services.journald.forwardToSyslog = true;

      system.stateVersion = "25.11";
    };
  };

  services.prometheus = let fixpoint = config.services.prometheus.exporters; in rec {
    enable = true;
    alertmanager = {
      enable = true;
      environmentFile = config.age.secrets."alertmanager/telegram".path;
      configuration = {
        route = {
          receiver = "telegram";
        };
        receivers = [
          {
            name = "telegram";
            telegram_configs = [{
              send_resolved = true;
              bot_token = "$TELEGRAM_BOT_TOKEN";
              chat_id = -1003849721555;
            }];
          }
        ];
      };
    };
    exporters = {
      node = {
        enable = true;
        enabledCollectors = [
          "diskstats"
          "filesystem"
          "cpu"
          "meminfo"
          "systemd"
          "cgroups"
        ];
      };
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
      srapeConfigs';
  };

  services.grafana.provision.dashboards.settings.providers = [{
    name = "default";
    options.path = pkgs.linkFarm "grafana-dashboards" [
      { name = "node-exporter.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-node-exporter; }
      { name = "cgroup.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-cgroup; }
    ];
  }];

  systemd.services.ipv6-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    script = ''
      ${pkgs.socat}/bin/socat -T 1 TCP-LISTEN:9101,reuseaddr,fork EXEC:"${pkgs.writeShellScript "ipv6-response" ''
        IP=$(${pkgs.iproute2}/bin/ip -j -6 addr show dev enp1s0 scope global | \
             ${pkgs.jq}/bin/jq -r '.[0].addr_info[] | select(.prefixlen == 128 and (.local | startswith("2001:"))) | .local')
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n$IP"
      ''}"
    '';
  };

  age = {
    rekey = {
      agePlugins = [ pkgs.age-plugin-fido2-hmac ];
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINMEbHrkxwZAsdv+V9moza0VTKY97R/qeennww20FUID";
    };
    secrets = {
      "alertmanager/telegram" = {
        rekeyFile = ./secrets/agenix/alertmanager/telegram.age;
      };
    };
  };

  system.stateVersion = "25.05";
}
