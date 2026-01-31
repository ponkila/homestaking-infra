{ lib
, config
, pkgs
, outputs
, ...
}:
let
  # General
  infra.ip = "192.168.100.50";
  sshKeysPath = "/var/mnt/nvme/secrets/ssh/id_ed25519";
in
{
  boot.initrd.availableKernelModules = [ "xfs" ];
  fileSystems."/var/mnt/nvme" = lib.mkImageMediaOverride {
    fsType = "xfs";
    device = "/dev/mapper/pro990-data";
    neededForBoot = true;
  };

  virtualisation.podman.enable = true;

  homestakeros = {
    # Localization options
    localization = {
      hostname = "kaakkuri-ephemeral-alpha";
      timezone = "Europe/Helsinki";
    };

    # SSH options
    ssh = {
      authorizedKeys = [
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIOdsfK46X5IhxxEy81am6A8YnHo2rcF2qZ75cHOKG7ToAAAACHNzaDprYXJp ssh:kari"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAILn/9IHTGC1sLxnPnLbtJpvF7HgXQ8xNkRwSLq8ay8eJAAAADHNzaDpzdGFybGFicw== ssh:starlabs"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIJuPW2qxz9ZvzcaO5RzcDr99t55PUBjmYC9ADX6sJhbjAAAABHNzaDo= ssh:muro"
      ];
      privateKeyFile = sshKeysPath;
    };

    # Lighthouse options
    consensus.lighthouse = {
      enable = true;
      endpoint = "http://${infra.ip}:5052";
      execEndpoint = "http://${infra.ip}:8551";
      dataDir = "/var/mnt/nvme/ethereum/mainnet/lighthouse";
      slasher = {
        enable = false;
        historyLength = 256;
        maxDatabaseSize = 16;
      };
      jwtSecretFile = "/var/mnt/nvme/ethereum/mainnet/jwt.hex";
      extraOptions = [
        "--log-format JSON"
        "--debug-level warn"
        "--metrics-address ${config.mesh.addressUnliteral}"
      ];
    };

    # Besu options
    execution.besu = {
      enable = true;
      endpoint = "http://${infra.ip}:8551";
      dataDir = "/var/mnt/nvme/ethereum/mainnet/besu";
      jwtSecretFile = "/var/mnt/nvme/ethereum/mainnet/jwt.hex";
      extraOptions = [
        "--host-allowlist=\"*\""
        "--nat-method=upnp"
        "--p2p-port=30303"
        "--sync-mode=SNAP"
        "--rpc-max-logs-range=60000"
        "--rpc-max-trace-filter-range=60000"
        "--bonsai-historical-block-limit=60000"
        "--cache-last-blocks=37000"
        "--metrics-host=${config.mesh.address}"
        "--metrics-port=9545"
        "--metrics-category=BLOCKCHAIN,ETHEREUM,EXECUTORS,JVM,NETWORK,PEERS,PERMISSIONING,PROCESS,PRUNER,RPC,SYNCHRONIZER,TRANSACTION_POOL,KVSTORE_ROCKSDB,KVSTORE_PRIVATE_ROCKSDB,KVSTORE_ROCKSDB_STATS,KVSTORE_PRIVATE_ROCKSDB_STATS"
        "--bonsai-limit-trie-logs-enabled=false"
        "--rpc-http-api=ETH,NET,WEB3,ADMIN"
        "--logging=WARN"
      ];
    };

    # Addons
    addons.mev-boost = {
      enable = true;
      endpoint = "http://${infra.ip}:18550";
    };

    addons.ssv-node = {
      dataDir = "/var/mnt/10-main/ethereum/mainnet/ssv";
    };

    # Wireguard options
    vpn.wireguard = {
      enable = true;
      configFile = "/var/mnt/nvme/secrets/wg0.conf";
    };

    mounts = {
      "10-main" = {
        enable = true;
        description = "nvme/single/samsung";
        what = "/dev/mapper/pro990-data";
        where = "/var/mnt/10-main";
        type = "xfs";
      };
    };
  };
  systemd.services.ssv-node.enable = false;

  systemd.network = {
    enable = true;
    networks = {
      "10-wan" = {
        linkConfig.RequiredForOnline = "routable";
        matchConfig.Name = "enp6s0";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
        };
        address = [ "192.168.1.25/24" ]; # static IP
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
        50001
        30303
        8546
      ];
      allowedUDPPorts = [
        50001
        30303
        8546
        51821
      ];
      interfaces."simple".allowedTCPPorts = [
        5054 # lighthouse
      ];
    };
    nameservers = [ "localhost:1053" ];
    useDHCP = false;
  };

  services.bitcoind."mainnet" = {
    enable = true;
    prune = "disable";
    dataDir = "/var/mnt/nvme/bitcoin/bitcoind";
    extraCmdlineOptions = [
      "-server=1"
      "-txindex=1"
      "-loglevelalways=1"
      "-logtimestamps=0"
    ];
    rpc = {
      port = 8332;
      users.core = {
        name = "core";
        passwordHMAC = "056759579170ff4e4204fa0e088787d5$f393d0f49d1067332a735619903d7a187bc198377f6b4d910f80b539c39854a6";
      };
    };
  };

  systemd.services.fulcrum = {
    enable = true;

    description = "fulcrum rpc";
    requires = [ "wg-quick-wg0.service" "bitcoind-mainnet.service" ];
    after = [ "wg-quick-wg0.service" "bitcoind-mainnet.service" ];

    script = ''${pkgs.fulcrum}/bin/Fulcrum \
      --datadir /var/mnt/nvme/bitcoin/fulcrum \
      --tcp ${infra.ip}:50001 \
      --stats 127.0.0.1:4224 \
      --bitcoind 127.0.0.1:8332 \
      --rpcuser core
    '';
    serviceConfig.Restart = "on-failure";
    serviceConfig.User = "bitcoind-mainnet";
    serviceConfig.Group = "bitcoind-mainnet";
    serviceConfig.EnvironmentFile = config.age.secrets.bitcoinConf.path;

    wantedBy = [ "multi-user.target" ];
  };

  systemd.tmpfiles.rules = [
    "d ${config.services.etcd.dataDir} 0755 etcd etcd -" # upsert directory
    "Z ${config.services.etcd.dataDir} - etcd etcd -" # recursively chown to user
    "Z ${config.services.bitcoind."mainnet".dataDir} - bitcoind-mainnet bitcoind-mainnet -"
    "Z /var/mnt/nvme/bitcoin/fulcrum - bitcoind-mainnet bitcoind-mainnet -"
  ];
  services.smartd = {
    enable = true;
    extraOptions = [
      "-A /var/log/smartd/"
      "--interval=600"
    ];
  };

  age = {
    generators.jwt = { pkgs, ... }: "${pkgs.openssl}/bin/openssl rand -hex 32";
    rekey = {
      agePlugins = [ pkgs.age-plugin-fido2-hmac ];
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF2U2OFXrH4ZT3gSYrTK6ZNkXTfGZQ5BhLh4cBelzzMF";
    };
    secrets = {
      bitcoinConf = {
        rekeyFile = ./secrets/agenix/bitcoin/rpcpassword.age;
        owner = config.services.bitcoind."mainnet".user;
        group = config.services.bitcoind."mainnet".group;
      };
    };
  };
  sops = {
    defaultSopsFile = ./secrets/default.yaml;
    age.sshKeyPaths = [ sshKeysPath ];
  };

  imports = [
    ../../nixosModules/mesh.nix
    ../../nixosModules/monitoring.nix
  ];

  mesh = {
    enable = true;
    endpoint = {
      ip = "eth.coditon.com";
      port = 51821;
    };
    etcd = {
      enable = true;
      dataDir = "/var/mnt/nvme/etcd";
      openFirewall = true;
    };
  };

  monitoring = {
    enable = true;
    grafana = {
      enable = true;
      address = infra.ip;
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
              bot_token_file = "/var/mnt/nvme/secrets/telegram.txt";
              chat_id = -4721018666;
            }];
          }
        ];
      };
    };
    exporters = {
      ebpf = {
        enable = true;
        names = [
          "biolatency"
        ];
      };
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
      smartctl = {
        enable = true;
        user = "root";
      };
      rasdaemon.enable = true;
      cgroup.enable = true;
      bitcoin = {
        user = "bitcoind-mainnet";
        rpcUser = "core";
        group = "bitcoind-mainnet";
        rpcPasswordFile = config.age.secrets.bitcoinConf.path; # no-op
        enable = true;
      };
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
          job_name = "besu";
          static_configs = [{ targets = [ "${config.mesh.address}:9545" ]; }];
        }
        {
          job_name = "lighthouse";
          static_configs = [{
            targets = [
              "${config.mesh.address}:5054"
              "${outputs.nixosConfigurations.ponkila-ephemeral-beta.config.mesh.address}:5054"
            ];
          }];
        }
      ];
    ruleFiles = with outputs.packages.x86_64-linux; [
      prometheus-alert-rasdaemon.outPath
      prometheus-alert-lighthouse.outPath
    ];
  };
  systemd.services.prometheus-bitcoin-exporter = {
    script = lib.mkForce ''
      exec ${config.services.prometheus.exporters.bitcoin.package}/bin/bitcoind-monitor.py
    '';
    serviceConfig.EnvironmentFile = config.age.secrets.bitcoinConf.path;
  };

  services.grafana.provision.dashboards.settings.providers = [{
    name = "default";
    options.path = pkgs.linkFarm "grafana-dashboards" [
      { name = "node-exporter.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-node-exporter; }
      { name = "besu.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-besu; }
      { name = "ebpf-biolatency.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-ebpf-biolatency; }
      { name = "smartctl.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-smartctl; }
      { name = "etcd.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-etcd; }
      { name = "cgroup.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-cgroup; }
    ];
  }];

  # Fix hardware quirk of Micron MTA9ASF2G72AZ-3G2F1 that reports critical temperature as 0 Celsius.
  # Max operating temperature is 95.
  # Would be better as a udev target but I could not figure how to make it work.
  systemd.services.jc42-temp-limits = {
    description = "Set JC42 temperature limits";
    after = [ "systemd-udev-settle.service" ];
    before = [ "prometheus.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = toString (pkgs.writeShellScript "set-jc42-limits" ''
        for hwmon in /sys/class/hwmon/hwmon*; do
          if [ "$(cat $hwmon/name 2>/dev/null)" = "jc42" ]; then
            echo 56000 > $hwmon/temp1_max
            echo 60000 > $hwmon/temp1_crit
          fi
        done
      '');
    };
  };

  system.stateVersion = "25.05";
}
