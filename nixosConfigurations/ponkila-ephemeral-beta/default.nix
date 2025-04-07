{ pkgs
, config
, lib
, inputs
, outputs
, ...
}:
let
  # General
  infra.ip = "192.168.100.10";
  lighthouse.datadir = "/var/mnt/xfs/lighthouse";
  sshKeysPath = "/var/mnt/xfs/secrets/ssh/id_ed25519";

  # Mesh
  inherit (inputs.clib.lib.network.ipv6) fromString;
  meshSelf = map (x: x.address) (map fromString config.systemd.network.networks."50-simple".address);
  clusterAddr = map (node: "${node.wirenix.peerName}=${toString (map (wg: "http://[${wg.address}]") (map fromString node.systemd.network.networks."50-simple".address))}:2380");
  hetzner = [ outputs.nixosConfigurations."hetzner-ephemeral-alpha".config ];
  kaakkuri = [ outputs.nixosConfigurations."kaakkuri-ephemeral-alpha".config ];
  ponkila = [ outputs.nixosConfigurations."ponkila-ephemeral-beta".config ];
in
{
  boot.initrd.availableKernelModules = [ "xfs" "dm_mod" "dm-raid" "dm_integrity" "raid0" ];
  # Workaround for https://github.com/Mic92/sops-nix/issues/24
  fileSystems."/var/mnt/xfs" = lib.mkImageMediaOverride {
    fsType = "xfs";
    device = "/dev/mapper/wd-ethereum";
    neededForBoot = true;
  };

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
      dataDir = lighthouse.datadir;
      slasher = {
        enable = false;
        historyLength = 256;
        maxDatabaseSize = 16;
      };
      jwtSecretFile = config.age.secrets."mainnet-jwt".path;
    };

    execution.besu = {
      enable = true;
      endpoint = "http://${infra.ip}:8551";
      dataDir = "/var/mnt/xfs/besu/mainnet";
      jwtSecretFile = "${config.age.secrets."mainnet-jwt".path}";
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
      dataDir = "/var/mnt/xfs/addons/ssv";
      privateKeyFile = config.sops.secrets."ssvnode/privateKey".path;
      privateKeyPasswordFile = config.sops.secrets."ssvnode/password".path;
    };

    mounts = {
      bitcoin = {
        enable = true;
        description = "bitcoin storage";

        what = "/dev/mapper/samsung-bitcoin";
        where = "/var/mnt/bitcoin";
        type = "xfs";

        before = [ "bitcoind-mainnet.service" ];
        wantedBy = [ "multi-user.target" ];
      };
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

  services.bitcoind."mainnet" = {
    enable = true;
    prune = "disable";
    dataDir = "/var/mnt/bitcoin/bitcoind";
    extraCmdlineOptions = [
      "-server=1"
      "-txindex=0"
      "-rpccookiefile=/var/mnt/bitcoin/bitcoind/.cookie"
    ];
  };

  systemd.services.electrs = {
    enable = true;

    description = "electrum rpc";
    requires = [ "wg-quick-wg0.service" "bitcoind-mainnet.service" ];
    after = [ "wg-quick-wg0.service" "bitcoind-mainnet.service" ];

    script = ''${pkgs.electrs}/bin/electrs \
      --db-dir /var/mnt/bitcoin/electrs/db \
      --cookie-file /var/mnt/bitcoin/bitcoind/.cookie \
      --network bitcoin \
      --electrum-rpc-addr 192.168.100.10:50001
    '';
    serviceConfig.Restart = "on-failure";

    wantedBy = [ "multi-user.target" ];
  };

  systemd.network = {
    enable = true;
    networks = {
      "10-fiber" = {
        linkConfig.RequiredForOnline = "routable";
        matchConfig.Name = "enp193s0f0";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
        };
        address = [ "192.168.17.20/24" ];
        routes = [
          {
            Gateway = "192.168.17.1";
            Metric = 2 * 1;
          }
        ];
      };
      "10-cellular" = {
        linkConfig.RequiredForOnline = "routable";
        matchConfig.Name = "enp66s0u1";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
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
      allowedTCPPorts = [ 50001 30303 8546 5432 8008 ];
      allowedUDPPorts = [ 50001 30303 8546 51821 ];
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
    };
  };
  sops = {
    defaultSopsFile = ./secrets/default.yaml;
    secrets."netdata/health_alarm_notify.conf" = {
      owner = "netdata";
      group = "netdata";
    };
    secrets."nix-serve/secretKeyFile" = { };
    secrets."ssvnode/password" = { };
    secrets."ssvnode/privateKey" = { };
    secrets."ssvnode/publicKey" = { };
    secrets."wireguard/wg0" = { };
    age.sshKeyPaths = [ sshKeysPath ];
  };

  services.netdata = {
    enable = true;
    configDir = {
      "health_alarm_notify.conf" = config.sops.secrets."netdata/health_alarm_notify.conf".path;
      "go.d/prometheus.conf" = pkgs.writeText "go.d/prometheus.conf" ''
        jobs:
          - name: etcd
            url: http://[${lib.concatStrings meshSelf}]:2379/metrics
      '';
    };
  };

  systemd.tmpfiles.rules = [
    # should be upstreamed, patroni is unable to start if it cannot create this folder
    "d /run/postgresql 0755 patroni patroni -"
  ];

  wirenix = {
    enable = true;
    peerName = "node2"; # defaults to hostname otherwise
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
    dataDir = "/var/mnt/xfs/etcd";
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
            "host   replication     all             ${lib.concatStrings (clusterReplicationIP hetzner)}/128     trust"
            "host   replication     all             ${lib.concatStrings (clusterReplicationIP kaakkuri)}/128    trust"
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
      postgresqlDataDir = "/var/mnt/kioxia/postgresql/${config.services.postgresql.package.psqlSchema}";
      nodeIp = lib.concatStrings (map (x: "[${x}]") meshSelf);
      otherNodesIps = clusterSiblingIPs (hetzner ++ kaakkuri);
      name = lib.concatStrings meshSelf;
      dataDir = "/var/mnt/kioxia/patroni";
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
