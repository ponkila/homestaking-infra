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

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.besu-mainnet = {
    enable = true;

    description = "mainnet el";
    requires = [ "wg-quick-wg0.service" ];
    after = [ "wg-quick-wg0.service" ];

    script = ''${pkgs.besu}/bin/besu \
      --network=mainnet \
      --rpc-http-enabled=true \
      --rpc-http-host=192.168.100.10 \
      --rpc-http-cors-origins="*" \
      --rpc-ws-enabled=true \
      --rpc-ws-host=0.0.0.0 \
      --host-allowlist="*" \
      --engine-host-allowlist="*" \
      --engine-rpc-enabled \
      --engine-jwt-secret=${config.age.secrets."mainnet-jwt".path} \
      --data-path=/var/mnt/xfs/besu/mainnet \
      --nat-method=upnp \
      --p2p-port=30303 \
      --sync-mode=CHECKPOINT \
      --engine-rpc-port=8551 \
      --rpc-http-port=8545 \
      --rpc-ws-port=8546 \
      --rpc-ws-authentication-enabled=false
    '';

    wantedBy = [ "multi-user.target" ];
  };

  systemd.network = {
    enable = true;
    networks = {
      "10-wan" = {
        linkConfig.RequiredForOnline = "routable";
        matchConfig.Name = "enp193s0f0";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
        };
        address = [ "192.168.17.20/24" ];
      };
      "10-usb" = {
        linkConfig.RequiredForOnline = "routable";
        matchConfig.Name = "enp66s0u1";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
        };
      };
    };
  };
  networking = {
    firewall = {
      allowedTCPPorts = [ 50001 30303 8546 ];
      allowedUDPPorts = [ 50001 30303 8546 51821 ];
    };
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
            url: http://127.0.0.1:2379/metrics
      '';
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/log/smartd 0755 netdata netdata -"
  ];
  services.smartd = {
    enable = true;
    extraOptions = [
      "-A /var/log/smartd/"
      "--interval=600"
    ];
  };

  wirenix = {
    enable = true;
    peerName = "node2"; # defaults to hostname otherwise
    configurer = "networkd"; # defaults to "static", could also be "networkd"
    keyProviders = [ "agenix-rekey" ]; # could also be ["agenix-rekey"] or ["acl" "agenix-rekey"]
    secretsDir = ../../nixosModules/wirenix/agenix; # only if you're using agenix-rekey
    aclConfig = import ../../nixosModules/wirenix/acl.nix;
  };

  services.etcd =
    let
      inherit (inputs.clib.lib.network.ipv6) fromString;
      self = map (x: x.address) (map fromString config.systemd.network.networks."50-simple".address);
      clusterAddr = map (node: "${node.wirenix.peerName}=${toString (map (wg: "http://[${wg.address}]") (map fromString node.systemd.network.networks."50-simple".address))}:2380");
      kaakkuri = clusterAddr [ outputs.nixosConfigurations."kaakkuri-ephemeral-alpha".config ];
      node1 = clusterAddr [ outputs.nixosConfigurations."hetzner-ephemeral-alpha".config ];
      node2 = clusterAddr [ outputs.nixosConfigurations."ponkila-ephemeral-beta".config ];
    in
    {
      enable = true;
      name = config.wirenix.peerName;
      listenPeerUrls = map (x: "http://[${x}]:2380") self;
      listenClientUrls = [ "http://localhost:2379" ] ++ (map (x: "http://[${x}]:2379") self);
      initialClusterToken = "etcd-cluster-1";
      initialClusterState = "new";
      initialCluster = kaakkuri ++ node1 ++ node2;
      dataDir = "/var/mnt/xfs/etcd";
      openFirewall = true;
    };

  system.stateVersion = "24.11";
}
