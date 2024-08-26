{ lib
, config
, pkgs
, inputs
, outputs
, ...
}:
let
  sshKeysPath = "/var/mnt/ssd/secrets/ssh/id_ed25519";
in
{
  boot.initrd.availableKernelModules = [ "xfs" ];
  fileSystems."/var/mnt/ssd" = lib.mkImageMediaOverride {
    fsType = "xfs";
    device = "/dev/mapper/samsung-ssd";
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
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAID5aw7sqJrXdKdNVu9IAyCCw1OYHXFQmFu/s/K+GAmGfAAAABHNzaDo= da@pusu"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINwWpZR5WuzyJlr7jYoe0mAYp+MJ12doozfqGz9/8NP/AAAABHNzaDo= da@pusu"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCkfHIgiK8S5awFn+oOdduS2mp5UGT4ki/ndoMArBol1dvRSKAdHS4okCX/umiy4BqAsDFkpYWuwe897NdOosba0iVyrFsYRou9FrOnQIMRIgtAvaOXeo2U4432glzH4WsMD+D+F4wHZ7walsrkaIPihpoHtWp8DkTPcFm1D8GP1o5TNpTjSFSuPFSzC2nburVcyfxZJluh/hxnxtYLNrmwOOHLhXcTmy5rQQ5u2HI5y64tS6fnKxxozA2gPaVro5+W5e3WtpSDGdd2NkPDzrMMmwYFEv4Tw9ooUfaJhXhq7AJakK/nTfpLquL9XSia8af+aOzx/p1v25f56dESlhNzcSlREP52hTA9T3foCA2IBkDitBeeGhUeeerQdczoRFxxSjoI244bPwAZ+tKIwO0XFaxLyd3jjzlya0F9w1N7wN0ZO4hY1NVv7oaYTUcU7TnvqGEMGLZpQBnIn7DCrUjKeW4AIUGvxcCP+F16lqFkuLSCgOAHM59NECVwBAOPGDk="
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJdbU8l66hVUAqk900GmEme5uhWcs05JMUQv2eD0j7MI juuso@starlabs"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIOdsfK46X5IhxxEy81am6A8YnHo2rcF2qZ75cHOKG7ToAAAACHNzaDprYXJp ssh:kari"
      ];
      privateKeyFile = sshKeysPath;
    };

    # Wireguard options
    vpn.wireguard = {
      enable = true;
      configFile = "/var/mnt/ssd/secrets/wg0.conf";
    };

  };

  systemd.services.lighthouse = {
    enable = true;

    description = "holesky cl";
    requires = [ "wg-quick-wg0.service" ];
    after = [ "wg-quick-wg0.service" ];

    script = ''${pkgs.lighthouse}/bin/lighthouse bn \
      --network holesky \
      --execution-endpoint http://localhost:8551 \
      --execution-jwt ${config.age.secrets."holesky-jwt".path} \
      --checkpoint-sync-url https://holesky.beaconstate.ethstaker.cc/ \
      --http \
      --datadir /var/mnt/ssd/ethereum/holesky/lighthouse \
      --builder http://127.0.0.1:18550 \
      --metrics
    '';

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.geth = {
    enable = true;

    description = "holesky el";
    requires = [ "wg-quick-wg0.service" ];
    after = [ "wg-quick-wg0.service" ];

    script = ''${pkgs.geth}/bin/geth \
      --datadir /var/mnt/ssd/ethereum/holesky/geth \
      --http --http.addr 192.168.100.50 --http.api="engine,eth,web3,net,debug" --http.port 8545 \
      --ws --ws.api="engine,eth,web3,net,debug" \
      --http.corsdomain "*" \
      --http.vhosts "*" \
      --holesky \
      --authrpc.jwtsecret=${config.age.secrets."holesky-jwt".path} \
      --metrics \
      --metrics.addr 127.0.0.1
    '';

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.mev-boost = {
    enable = true;

    description = "holesky mev";
    requires = [ "wg-quick-wg0.service" ];
    after = [ "wg-quick-wg0.service" ];

    script = ''${pkgs.mev-boost}/bin/mev-boost \
      -holesky \
      -addr 127.0.0.1:18550 \
      -relay-check \
      -relays "https://0xafa4c6985aa049fb79dd37010438cfebeb0f2bd42b115b89dd678dab0670c1de38da0c4e9138c9290a398ecd9a0b3110@boost-relay-holesky.flashbots.net"
    '';

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.ssvnode =
    let
      c = pkgs.writeText "config.yaml" ''
        global:
          LogFileBackups: 28
          LogFilePath: /var/mnt/ssd/ethereum/holesky/ssvnode/debug.log
          LogLevel: info

        db:
          Path: /var/mnt/ssd/ethereum/holesky/ssvnode/db

        ssv:
          Network: holesky
          ValidatorOptions:
            BuilderProposals: true

        eth2:
          BeaconNodeAddr: http://localhost:5052

        eth1:
          ETH1Addr: ws://localhost:8546

        p2p:
          # Optionally provide the external IP address of the node, if it cannot be automatically determined.
          # HostAddress: 192.168.1.1

          # Optionally override the default TCP & UDP ports of the node.
          # TcpPort: 13001
          # UdpPort: 12001

        KeyStore:
          PrivateKeyFile: ${config.sops.secrets."holesky/ssvnode/privateKey".path}
          PasswordFile: ${config.sops.secrets."holesky/ssvnode/password".path}

        MetricsAPIPort: 15000
      '';
    in
    {
      enable = true;

      description = "holesky ssvnode";

      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 5;
      };

      script = ''${pkgs.ssvnode}/bin/ssvnode start-node -c ${c}'';

      wantedBy = [ "multi-user.target" ];
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
      };
    };
  };
  networking = {
    firewall = {
      allowedTCPPorts = [
        # NAT routes
        13001 # SSV
        30303 # geth discovery
        9001 # lighthouse discovery

        # Internal
        50001 # electrs
        8545 # holesky RPC
      ];
      allowedUDPPorts = [
        12001
        30303
        51821
        9001

        50001
        8545
      ];
    };
    useDHCP = false;
  };

  services.bitcoind."mainnet" = {
    enable = true;
    prune = "disable";
    dataDir = "/var/mnt/ssd/bitcoin/bitcoind";
    extraCmdlineOptions = [
      "-server=1"
      "-txindex=0"
      "-rpccookiefile=/var/mnt/ssd/bitcoin/bitcoind/.cookie"
    ];
  };

  systemd.services.electrs = {
    enable = true;

    description = "electrum rpc";
    requires = [ "wg-quick-wg0.service" "bitcoind-mainnet.service" ];
    after = [ "wg-quick-wg0.service" "bitcoind-mainnet.service" ];

    script = ''${pkgs.electrs}/bin/electrs \
      --db-dir /var/mnt/ssd/bitcoin/electrs/db \
      --cookie-file /var/mnt/ssd/bitcoin/bitcoind/.cookie \
      --network bitcoin \
      --electrum-rpc-addr 192.168.100.50:50001 \
      --monitoring-addr 127.0.0.1:4224
    '';

    wantedBy = [ "multi-user.target" ];
  };

  services.netdata = {
    enable = true;
    configDir = {
      "health_alarm_notify.conf" = config.sops.secrets."netdata/health_alarm_notify.conf".path;
      "go.d/prometheus.conf" = pkgs.writeText "go.d/prometheus.conf" ''
        jobs:
          - name: ssv
            url: http://127.0.0.1:15000/metrics
          - name: ssv_health
            url: http://127.0.0.1:15000/health
          - name: geth
            url: http://127.0.0.1:6060/debug/metrics/prometheus
          - name: lighthouse
            url: http://127.0.0.1:5054/metrics
          - name: electrs
            url: http://127.0.0.1:4224/metrics
      '';
      "health.d/ssv_node_status" = pkgs.writeText "health.d/ssv_node_status.conf" ''
        alarm: jesse, juuso: ssv_node_status
        lookup: min -10s
        on: prometheus_ssv.ssv_node_status
        every: 10s
        warn: $this == 0
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

  age = {
    generators.jwt = { pkgs, ... }: "${pkgs.openssl}/bin/openssl rand -hex 32";
    rekey = {
      agePlugins = [ pkgs.age-plugin-fido2-hmac ];
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF2U2OFXrH4ZT3gSYrTK6ZNkXTfGZQ5BhLh4cBelzzMF";
    };
    secrets = {
      holesky-jwt = {
        rekeyFile = ./secrets/agenix/holesky-jwt.age;
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
    secrets."holesky/ssvnode/password" = { };
    secrets."holesky/ssvnode/privateKey" = { };
    secrets."holesky/ssvnode/publicKey" = { };
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
      listenClientUrls = map (x: "http://[${x}]:2379") self;
      initialClusterToken = "etcd-cluster-1";
      initialClusterState = "new";
      initialCluster = kaakkuri ++ node1 ++ node2;
      dataDir = "/var/mnt/ssd/etcd";
      openFirewall = true;
    };

  system.stateVersion = "24.05";
}
