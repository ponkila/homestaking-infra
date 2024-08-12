{ pkgs
, config
, lib
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

  systemd.services.besu-holesky = {
    enable = true;

    description = "holesky el";
    requires = [ "wg-quick-wg0.service" ];
    after = [ "wg-quick-wg0.service" ];

    script = ''${pkgs.besu}/bin/besu \
      --network=holesky \
      --rpc-http-enabled=true \
      --rpc-http-host=127.0.0.1 \
      --rpc-http-cors-origins="*" \
      --rpc-ws-enabled=true \
      --rpc-ws-host=127.0.0.1 \
      --host-allowlist="*" \
      --engine-host-allowlist="*" \
      --engine-rpc-enabled \
      --engine-jwt-secret=${config.age.secrets."holesky-jwt".path} \
      --data-path=/var/mnt/xfs/besu/holesky \
      --nat-method=upnp \
      --p2p-port=30342 \
      --sync-mode=SNAP \
      --engine-rpc-port=8424 \
      --rpc-http-port=8542 \
      --rpc-ws-port=8543
    '';

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.lighthouse-holesky = {
    enable = true;

    description = "holesky cl";
    requires = [ "wg-quick-wg0.service" ];
    after = [ "wg-quick-wg0.service" ];

    script = ''${pkgs.lighthouse}/bin/lighthouse bn \
      --network holesky \
      --execution-endpoint http://localhost:8424 \
      --execution-jwt ${config.age.secrets."holesky-jwt".path} \
      --checkpoint-sync-url https://holesky.beaconstate.ethstaker.cc/ \
      --http \
      --datadir /var/mnt/xfs/lighthouse/holesky \
      --port 9424
    '';

    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [ 50001 30303 30342 9424 ];
  networking.firewall.allowedUDPPorts = [ 50001 30303 30342 9424 ];

  # Secrets
  age = {
    rekey = {
      agePlugins = [ pkgs.age-plugin-fido2-hmac ];
      hostPubkey = "age1rahna5rce9mj0js0p7dgt6wseqyzxjawva82tfdelzuvmngr5fdqa2geuy";
    };
    secrets = {
      mainnet-jwt = {
        rekeyFile = ./secrets/agenix/mainnet-jwt.age;
        generator.script = "hex";
      };
      holesky-jwt = {
        rekeyFile = ./secrets/agenix/holesky-jwt.age;
        generator.script = "hex";
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
    };
  };

  wirenix = {
    enable = true;
    peerName = "node2"; # defaults to hostname otherwise
    configurer = "networkd"; # defaults to "static", could also be "networkd"
    keyProviders = [ "agenix-rekey" ]; # could also be ["agenix-rekey"] or ["acl" "agenix-rekey"]
    secretsDir = ../../nixosModules/wirenix/agenix; # only if you're using agenix-rekey
    aclConfig = import ../../nixosModules/wirenix/acl.nix;
  };

  system.stateVersion = "24.05";
}
