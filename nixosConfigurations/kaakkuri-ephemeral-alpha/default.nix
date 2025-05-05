{ lib
, config
, pkgs
, inputs
, outputs
, ...
}:
let
  # General
  infra.ip = "192.168.100.50";
  sshKeysPath = "/var/mnt/nvme/secrets/ssh/id_ed25519";

  # Mesh
  inherit (inputs.clib.lib.network.ipv6) fromString;
  meshSelf = map (x: x.address) (map fromString config.systemd.network.networks."50-simple".address);
  clusterAddr = map (node: "${node.wirenix.peerName}=${toString (map (wg: "http://[${wg.address}]") (map fromString node.systemd.network.networks."50-simple".address))}:2380");
  hetzner = [ outputs.nixosConfigurations."hetzner-ephemeral-alpha".config ];
  kaakkuri = [ outputs.nixosConfigurations."kaakkuri-ephemeral-alpha".config ];
  ponkila = [ outputs.nixosConfigurations."ponkila-ephemeral-beta".config ];
in
{
  boot.initrd.availableKernelModules = [ "xfs" ];
  fileSystems."/var/mnt/nvme" = lib.mkImageMediaOverride {
    fsType = "xfs";
    device = "/dev/mapper/pro990-data";
    neededForBoot = true;
  };

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
    };

    # Besu options
    execution.besu = {
      enable = true;
      endpoint = "http://${infra.ip}:8551";
      dataDir = "/var/mnt/nvme/ethereum/mainnet/besu";
      jwtSecretFile = "/var/mnt/nvme/ethereum/mainnet/jwt.hex";
      extraOptions = [
        "--nat-method=upnp"
        "--p2p-port=30303"
        "--sync-mode=CHECKPOINT"
        "--host-allowlist=\"*\""
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
        5432
        8008
      ];
      allowedUDPPorts = [
        50001
        30303
        8546
        51821
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
      "-txindex=0"
      "-rpccookiefile=/var/mnt/nvme/bitcoin/bitcoind/.cookie"
    ];
  };

  systemd.services.electrs = {
    enable = true;

    description = "electrum rpc";
    requires = [ "wg-quick-wg0.service" "bitcoind-mainnet.service" ];
    after = [ "wg-quick-wg0.service" "bitcoind-mainnet.service" ];

    script = ''${pkgs.electrs}/bin/electrs \
      --db-dir /var/mnt/nvme/bitcoin/electrs/db \
      --cookie-file /var/mnt/nvme/bitcoin/bitcoind/.cookie \
      --network bitcoin \
      --electrum-rpc-addr ${infra.ip}:50001 \
      --monitoring-addr 127.0.0.1:4224
    '';
    serviceConfig.Restart = "on-failure";

    wantedBy = [ "multi-user.target" ];
  };

  services.netdata = {
    enable = true;
    configDir = {
      "health_alarm_notify.conf" = config.sops.secrets."netdata/health_alarm_notify.conf".path;
      "go.d/prometheus.conf" = pkgs.writeText "go.d/prometheus.conf" ''
        jobs:
          - name: electrs
            url: http://127.0.0.1:4224/metrics
          - name: besu
            url: http://127.0.0.1:9545/metrics
          - name: etcd
            url: http://[${lib.concatStrings meshSelf}]:2379/metrics
          - name: patroni
            url: http://[${lib.concatStrings meshSelf}]:8008/metrics
          - name: coredns
            url: http://localhost:9153/metrics
      '';
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/log/smartd 0755 netdata netdata -"
    "d /run/postgresql 0755 patroni patroni -"
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
    secrets = { };
  };
  sops = {
    defaultSopsFile = ./secrets/default.yaml;
    secrets."netdata/health_alarm_notify.conf" = {
      owner = "netdata";
      group = "netdata";
    };
    age.sshKeyPaths = [ sshKeysPath ];
  };

  wirenix = {
    enable = true;
    peerName = "kaakkuri"; # defaults to hostname otherwise
    configurer = "networkd"; # defaults to "static", could also be "networkd"
    keyProviders = [ "agenix-rekey" ]; # could also be ["agenix-rekey"] or ["acl" "agenix-rekey"]
    secretsDir = ../../nixosModules/wirenix/agenix; # only if you're using agenix-rekey
    aclConfig = import ../../nixosModules/wirenix/acl.nix;
  };

  services.etcd = {
    enable = true;
    name = config.wirenix.peerName;
    listenPeerUrls = map (x: "http://[${x}]:2380") meshSelf;
    listenClientUrls = map (x: "http://[${x}]:2379") meshSelf;
    initialClusterToken = "etcd-cluster-1";
    initialClusterState = "new";
    initialCluster =
      clusterAddr hetzner ++
      clusterAddr kaakkuri ++
      clusterAddr ponkila;
    dataDir = "/var/mnt/nvme/etcd";
    openFirewall = true;
  };

  services.patroni =
    let
      clusterListenURLs = map (node: "${toString (map (wg: "[${wg.address}]") (map fromString node.systemd.network.networks."50-simple".address))}:2379");
      clusterSiblingIPs = map (node: "${toString (map (wg: "[${wg.address}]") (map fromString node.systemd.network.networks."50-simple".address))}");
      clusterReplicationIP = map (node: "${toString (map (wg: "${wg.address}") (map fromString node.systemd.network.networks."50-simple".address))}");
    in
    {
      enable = true;
      postgresqlPackage = pkgs.postgresql_16;
      scope = "ponkila";
      settings = {
        etcd3 = {
          hosts = lib.concatStringsSep "," (clusterListenURLs (hetzner ++ kaakkuri ++ ponkila));
        };
        postgresql = {
          pg_hba = [
            "local  all             all             trust"
            "host   all             all             ${lib.concatStrings meshSelf}/128                           trust"
            "host   replication     all             ${lib.concatStrings meshSelf}/128                           trust"
            "host   replication     all             ${lib.concatStrings (clusterReplicationIP ponkila)}/128     trust"
            "host   replication     all             ${lib.concatStrings (clusterReplicationIP hetzner)}/128     trust"
          ];
          authentication = {
            replication = {
              username = "repl";
              password = "fizzbuzz";
            };
            superuser = {
              username = "dba";
              password = "foobar";
            };
          };
        };
      };
      postgresqlDataDir = "/var/mnt/nvme/postgresql/${config.services.postgresql.package.psqlSchema}";
      nodeIp = lib.concatStrings (map (x: "[${x}]") meshSelf);
      otherNodesIps = clusterSiblingIPs (hetzner ++ ponkila);
      name = lib.concatStrings meshSelf;
      dataDir = "/var/mnt/nvme/patroni";
    };

  services.coredns = {
    enable = true;
    config = ''
      ponkila.nix:1053 {
        etcd {
          path /skydns
          endpoint ${lib.concatStringsSep " " config.services.etcd.listenClientUrls}
        }
        prometheus
        loadbalance
      }

      .:1053 {
        forward . 1.1.1.2 2606:4700:4700::1112
        cache
      }
    '';
  };

  systemd.services.wheres-the-postgres =
    let
      wheres-the-postgres = pkgs.callPackage ../../packages/wheres-the-postgres { inherit config; };
    in
    {
      enable = true;
      after = [ "etcd.service" "coredns.service" ];
      requires = [ "etcd.service" "coredns.service" ];
      script = "${wheres-the-postgres}/bin/wheres-the-postgres";
      serviceConfig.Restart = "on-failure";
      wantedBy = [ "multi-user.target" ];
    };

  system.stateVersion = "24.11";
}
