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
      enable = false;
      endpoint = "http://${infra.ip}:8551";
      dataDir = "/var/mnt/nvme/ethereum/mainnet/besu";
      jwtSecretFile = "/var/mnt/nvme/ethereum/mainnet/jwt.hex";
      extraOptions = [
        "--bonsai-historical-block-limit=60000"
        "--bonsai-limit-trie-logs-enabled=false"
        "--cache-last-blocks=37000"
        "--host-allowlist=\"*\""
        "--logging=WARN"
        "--metrics-category=BLOCKCHAIN,ETHEREUM,EXECUTORS,JVM,NETWORK,PEERS,PERMISSIONING,PROCESS,PRUNER,RPC,SYNCHRONIZER,TRANSACTION_POOL,KVSTORE_ROCKSDB,KVSTORE_PRIVATE_ROCKSDB,KVSTORE_ROCKSDB_STATS,KVSTORE_PRIVATE_ROCKSDB_STATS"
        "--metrics-host=${config.mesh.address}"
        "--metrics-port=9545"
        "--nat-method=upnp"
        "--p2p-port=30303"
        "--profile=PERFORMANCE"
        "--rpc-http-api=ETH,NET,WEB3,ADMIN"
        "--rpc-max-logs-range=60000"
        "--sync-mode=SNAP"
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
      "20-ssd" = {
        enable = true;
        description = "ssd/single/samsung";
        what = "/dev/mapper/qvo870-ssd1";
        where = "/var/mnt/20-ssd";
        type = "xfs";
      };
    };
  };
  systemd.services.ssv-node.enable = false;

  systemd.services.reth =
    let
      baseDir = "/var/mnt/nvme/ethereum/mainnet/reth";
    in
    {
      enable = true;

      script = ''${outputs.packages.x86_64-linux.reth}/bin/reth node \
        --authrpc.addr ${infra.ip} \
        --authrpc.jwtsecret /var/mnt/nvme/ethereum/mainnet/jwt.hex \
        --authrpc.port 8551 \
        --chain mainnet \
        --color never \
        --datadir ${baseDir} \
        --datadir.pprof-dumps ${baseDir}/pprof_dumps \
        --datadir.static-files ${baseDir}/static_files \
        --engine.persistence-backpressure-threshold 160 \
        --engine.persistence-threshold 128 \
        --engine.state-provider-metrics \
        --http --http.api all --http.addr ${infra.ip} \
        --metrics 127.0.0.1:7384 \
        --rpc-cache.max-receipts 60000 \
        --rpc.max-blocks-per-filter 360000 \
        --rpc.max-logs-per-response 360000 \
        --storage.v2 true \
        --ws --ws.addr ${infra.ip} --ws.origins "*" --ws.api all
      '';
      serviceConfig.Restart = "always";

      after = [ "wg-quick-wg0.service" ];
      wantedBy = [ "multi-user.target" ];
    };

  systemd.network = {
    enable = true;
    networks = {
      "10-wan" = {
        linkConfig.RequiredForOnline = "routable";
        matchConfig.Name = "enp6s0";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
          IPv6PrivacyExtensions = "prefer-public";
        };
        dhcpV6Config = {
          DUIDType = "link-layer";
        };
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
        50001 # fulcrum
        30303 # besu p2p
        8546 # besu websocket
        9100 # prometheus exporters
        9090 # prometheus ui
        3000 # grafana
      ];
      allowedUDPPorts = [
        50001
        30303
        8546
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
    dataDir = "/var/mnt/20-ssd/bitcoin/bitcoind";
    dbCache = 1024;
    extraCmdlineOptions = [
      "-server=1"
      "-txindex=1"
      "-loglevelalways=1"
      "-logtimestamps=0"
      "-onlynet=ipv4"
      "-onlynet=ipv6"
      "-listen=0"
    ];
    rpc = {
      port = 8332;
      users.core = {
        name = "core";
        passwordHMAC = "056759579170ff4e4204fa0e088787d5$f393d0f49d1067332a735619903d7a187bc198377f6b4d910f80b539c39854a6";
      };
    };
  };

  systemd.services.fulcrum =
    let
      cfg = pkgs.writeText "fulcum.conf" ''
        peering = false
      '';
    in
    {
      enable = true;

      description = "fulcrum rpc";
      requires = [ "wg-quick-wg0.service" "bitcoind-mainnet.service" ];
      after = [ "wg-quick-wg0.service" "bitcoind-mainnet.service" ];

      script = ''${pkgs.fulcrum}/bin/Fulcrum \
      --datadir /var/mnt/20-ssd/bitcoin/fulcrum \
      --tcp ${infra.ip}:50001 \
      --stats 127.0.0.1:4224 \
      --bitcoind 127.0.0.1:8332 \
      --rpcuser core \
      --ts-format none \
      ${cfg}
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
    "Z /var/mnt/20-ssd/bitcoin/fulcrum - bitcoind-mainnet bitcoind-mainnet -"
  ];

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
        inherit (config.services.bitcoind."mainnet") group;
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
              chat_id = -1003849721555;
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
          job_name = "reth";
          static_configs = [{ targets = [ "127.0.0.1:7384" ]; }];
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
      { name = "cgroup.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-cgroup; }
      { name = "ebpf-biolatency.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-ebpf-biolatency; }
      { name = "etcd.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-etcd; }
      { name = "node-exporter.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-node-exporter; }
      { name = "reth.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-reth; }
      { name = "smartctl.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-smartctl; }
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
