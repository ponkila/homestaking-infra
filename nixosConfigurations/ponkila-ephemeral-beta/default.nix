{ pkgs
, config
, lib
, outputs
, ...
}:
let
  # General
  infra.ip = "192.168.100.10";
  sshKeysPath = "/var/mnt/xfs/secrets/ssh/id_ed25519";
in
{
  boot.initrd.availableKernelModules = [ "xfs" "dm_mod" "dm-raid" "dm_integrity" "raid0" ];
  fileSystems."/var/mnt/xfs" = lib.mkImageMediaOverride {
    fsType = "xfs";
    device = "/dev/mapper/wd-ethereum";
    neededForBoot = true;
  };

  virtualisation.podman.enable = true;

  homestakeros = {
    # Localization options
    localization = {
      hostname = "ponkila-ephemeral-beta";
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

    # Wireguard options
    vpn.wireguard = {
      enable = true;
      configFile = config.sops.secrets."wireguard/wg0".path;
    };

    # Lighthouse options
    consensus.lighthouse = {
      enable = true;
      endpoint = "http://${infra.ip}:5052";
      execEndpoint = "http://${infra.ip}:8551";
      dataDir = "/var/mnt/xfs/lighthouse";
      slasher = {
        enable = false;
        historyLength = 256;
        maxDatabaseSize = 16;
      };
      jwtSecretFile = config.age.secrets."mainnet-jwt".path;
      extraOptions = [
        "--log-format JSON"
        "--debug-level warn"
        "--metrics-address ${config.mesh.addressUnliteral}"
      ];
    };

    # Addons
    addons.mev-boost = {
      enable = true;
      endpoint = "http://${infra.ip}:18550";
    };

    addons.ssv-node = {
      dataDir = "/var/mnt/kioxia/ssv";
    };

    mounts = {
      kioxia = {
        enable = true;
        description = "nvme/single/kioxia";

        what = "/dev/mapper/kioxia-exceria_pro";
        where = "/var/mnt/kioxia";
        type = "xfs";

        wantedBy = [ "multi-user.target" ];
      };
    };
  };
  systemd.services.ssv-node.enable = false;

  services.bitcoind."mainnet" = {
    enable = true;
    prune = "disable";
    dataDir = "/var/mnt/kioxia/bitcoin/bitcoind";
    extraCmdlineOptions = [
      "-server=1"
      "-txindex=1"
      "-loglevelalways=1"
      "-logtimestamps=0"
      "-onlynet=ipv4"
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
  systemd.services.bitcoind-mainnet.requires = [ "var-mnt-kioxia.mount" ];
  systemd.services.bitcoind-mainnet.after = [ "var-mnt-kioxia.mount" ];

  systemd.services.reth =
    let
      baseDir = "/var/mnt/xfs/reth";
    in
    {
      enable = true;

      script = ''${outputs.packages.x86_64-linux.reth}/bin/reth node \
        --authrpc.addr ${infra.ip} \
        --authrpc.jwtsecret ${config.age.secrets."mainnet-jwt".path} \
        --authrpc.port 8551 \
        --chain mainnet \
        --color never \
        --datadir ${baseDir} \
        --datadir.pprof-dumps ${baseDir}/pprof-dumps \
        --datadir.static-files ${baseDir}/static-files \
        --engine.persistence-threshold 128 \
        --engine.state-provider-metrics \
        --http --http.api all --http.addr ${infra.ip} \
        --metrics 127.0.0.1:7384 \
        --rpc.max-blocks-per-filter 360000 \
        --rpc.max-logs-per-response 360000 \
        --tracing-otlp=http://localhost:4318/v1/traces \
        --ws --ws.addr ${infra.ip} --ws.origins "*" --ws.api all
      '';
      serviceConfig.Restart = "always";

      wantedBy = [ "multi-user.target" ];
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
      --datadir /var/mnt/kioxia/bitcoin/fulcrum \
      --tcp ${infra.ip}:50001 \
      --stats 127.0.0.1:4225 \
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

  systemd.network = {
    enable = true;
    networks = {
      "10-fiber" = {
        linkConfig.RequiredForOnline = "routable";
        matchConfig.Name = "enp1s0f0";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
        };
        address = [ "192.168.17.20/24" ];
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

  # Secrets
  age = {
    generators.jwt = { pkgs, ... }: "${pkgs.openssl}/bin/openssl rand -hex 32";
    rekey = {
      agePlugins = [ pkgs.age-plugin-fido2-hmac ];
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPwLwYmyCmUJAi82j5py4rwNX9vpM7EVLo/NEMnZg74H";
    };
    secrets = {
      mainnet-jwt = {
        rekeyFile = ./secrets/agenix/mainnet-jwt.age;
        generator.script = "jwt";
      };
      bitcoinConf = {
        rekeyFile = ./secrets/agenix/bitcoin/rpcpassword.age;
        owner = config.services.bitcoind."mainnet".user;
        group = config.services.bitcoind."mainnet".group;
      };
    };
  };
  sops = {
    defaultSopsFile = ./secrets/default.yaml;
    secrets."nix-serve/secretKeyFile" = { };
    secrets."ssvnode/password" = {
      path = "/var/mnt/kioxia/ssv/password";
    };
    secrets."ssvnode/privateKey" = {
      path = "/var/mnt/kioxia/ssv/ssv_operator_key";
    };
    secrets."ssvnode/publicKey" = {
      path = "/var/mnt/kioxia/ssv/ssv_operator_key.pub";
    };
    secrets."wireguard/wg0" = { };
    age.sshKeyPaths = [ sshKeysPath ];
  };

  systemd.tmpfiles.rules = [
    "d ${config.services.etcd.dataDir} 0755 etcd etcd -" # upsert directory
    "Z ${config.services.etcd.dataDir} - etcd etcd -" # recursively chown to user
    "Z ${config.services.bitcoind."mainnet".dataDir} - bitcoind-mainnet bitcoind-mainnet -"
    "Z /var/mnt/kioxia/bitcoin/electrs - bitcoind-mainnet bitcoind-mainnet -"
    "Z /var/mnt/kioxia/bitcoin/fulcrum - bitcoind-mainnet bitcoind-mainnet -"
  ];

  imports = [
    ../../nixosModules/mesh.nix
    ../../nixosModules/monitoring.nix
  ];
  mesh = {
    enable = true;
    endpoint = {
      ip = "nyt2.ponkila.com";
      port = 51821;
    };
    etcd = {
      enable = true;
      dataDir = "/var/mnt/xfs/etcd";
      openFirewall = true;
    };
  };

  services.chrony = {
    enable = true;
    servers = [
      "time.cloudflare.com"
      "ntp1.hetzner.de"
      "time.mikes.fi"
    ];
  };

  monitoring = {
    enable = true;
    grafana = {
      enable = true;
      address = infra.ip;
    };
    logs = true;
    traces = true;
    alerts = true;
  };

  environment.systemPackages = with pkgs; [
    freeipmi
  ];

  services.prometheus = let fixpoint = config.services.prometheus.exporters; in rec {
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
              bot_token_file = "/var/mnt/xfs/secrets/telegram.txt";
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
      ipmi =
        let
          ipmiExporterConfig = pkgs.writeText "ipmi-exporter.yml" ''
            modules:
              default:
                collectors:
                  - ipmi
                  - bmc
                  - bmc-watchdog
                  - sel
                  - sel-events
          '';
        in
        {
          enable = true;
          user = "root";
          group = "root";
          configFile = ipmiExporterConfig;
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
              "${outputs.nixosConfigurations.kaakkuri-ephemeral-alpha.config.mesh.address}:5054"
            ];
          }];
        }
      ];
    ruleFiles = with outputs.packages.x86_64-linux; [
      prometheus-alert-ipmi.outPath
      prometheus-alert-rasdaemon.outPath
      prometheus-alert-lighthouse.outPath
    ];
  };
  systemd.services.prometheus-ipmi-exporter.serviceConfig = {
    DynamicUser = lib.mkForce false;
    PrivateDevices = lib.mkForce false;
    DeviceAllow = lib.mkForce [ "/dev/ipmi0 rw" ];
    ProtectKernelModules = lib.mkForce false;
    ProtectKernelTunables = lib.mkForce false;
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
      { name = "ebpf-biolatency.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-ebpf-biolatency; }
      { name = "smartctl.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-smartctl; }
      { name = "reth.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-reth; }
      { name = "etcd.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-etcd; }
      { name = "cgroup.json"; path = outputs.packages.x86_64-linux.grafana-dashboard-cgroup; }
    ];
  }];

  system.stateVersion = "25.05";
}
