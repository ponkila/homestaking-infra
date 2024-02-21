{
  pkgs,
  config,
  inputs,
  outputs,
  lib,
  ...
}: let
  # General
  sshKeysPath = "/var/mnt/secrets/ssh/id_ed25519";
  ponkila-ephemeral-beta = outputs.nixosConfigurations.ponkila-ephemeral-beta.config.homestakeros;
in {
  boot.initrd.availableKernelModules = [
    "virtio"
    "virtio_rng"
    "virtio_console"
    "virtio_balloon"
    "virtio_scsi"
    "virtio_gpu"
    "virtio_pci"
    "virtio_net"

    "btrfs"
  ];
  # Workaround for https://github.com/Mic92/sops-nix/issues/24
  fileSystems."/var/mnt/secrets" = lib.mkImageMediaOverride {
    fsType = "btrfs";
    device = "/dev/sda";
    options = ["subvolid=256"];
    neededForBoot = true;
  };

  environment.systemPackages = with pkgs; [
    blutgang
    keep-core
  ];

  environment.etc."blutgang.toml" = {
    text = ''
      [blutgang]
      # Clear the cache DB on startup
      do_clear = false
      # Where to bind blutgang to
      address = "192.168.100.40:8545"
      # Moving average length for the latency
      ma_length = 10
      # Sort RPCs by latency on startup. Recommended to leave on.
      sort_on_startup = true
      # Enable health checking
      health_check = true
      # Acceptable time to wait for a response in ms
      ttl = 300
      # How many times to retry a request before giving up
      max_retries = 32
      # Time between health checks in ms
      health_check_ttl = 12000

      # Note: the admin namespace contains volatile functions and
      # should not be exposed publicly.
      [admin]
      # Enable the admin namespace
      enabled = false
      # Address for the admin RPC
      address = "127.0.0.1:5715"
      # Only allow read-only methods
      # Recommended `true` unless you 100% need write methods
      readonly = true
      # Enable the use of JWT for auth
      # Should be on if exposing to the internet
      jwt = false
      # jwt token
      key = ""

      # Sled config
      # Sled is the database we use for our cache, for more info check their docs
      [sled]
      # Path to db
      db_path = "/var/mnt/blutgang"
      # sled mode. Can be HighThroughput/LowSpace
      mode = "HighThroughput"
      # Cache size in bytes. Doesn't matter too much as you OS should also be caching.
      cache_capacity = 1000000000
      # Use zstd compression. Reduces size 60-70%,
      # and increases CPU and latency by around 10% for db writes and 2% for reads
      compression = true
      # Print DB profile when dropped. Doesn't do anything for now.
      print_profile = false
      # Frequency of flushes in ms
      flush_every_ms = 24000

      [ponkila-ephemeral-beta]
      url = "http://192.168.100.10:8545"
      ws_url = "ws://192.168.100.10:8546"
      # The maximum ammount of time we can use this rpc in a row.
      max_consecutive = 5
      # Max ammount of querries per second. Doesn't do anything for now.
      max_per_second = 0

      [dinar-ephemeral-alpha]
      url = "http://192.168.100.31:8545"
      #ws_url = "ws://192.168.100:31:8546"
      max_consecutive = 5
      max_per_second = 0

      [dinar-ephemeral-beta]
      url = "http://192.168.100.32:8545"
      #ws_url = "ws://192.168.100.32:8546"
      max_consecutive = 5
      max_per_second = 0
    '';
  };

  systemd.services.blutgang = {
    enable = true;

    description = "blutgang ethereum rpc proxy";
    requires = ["wg-quick-wg0.service"];
    after = ["wg-quick-wg0.service"];

    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
      User = "core";
      Group = "core";
      Type = "simple";
    };

    script = ''      ${pkgs.blutgang}/bin/blutgang \
            -c /etc/blutgang.toml
    '';

    wantedBy = ["multi-user.target"];
  };

  environment.etc."keep-config.toml" = {
    text = ''
      [ethereum]
      URL = "ws://192.168.100.40:8545"
      KeyFile = "${config.sops.secrets."keep-network/operator-key".path}"

      # Uncomment to override the defaults for transaction status monitoring.

      # MiningCheckInterval is the interval in which transaction
      # mining status is checked. If the transaction is not mined within this
      # time, the gas price is increased and transaction is resubmitted.
      #
      # MiningCheckInterval = 60  # 60 sec (default value)

      # MaxGasFeeCap specifies the maximum gas fee cap the client is
      # willing to pay for the transaction to be mined. The offered transaction
      # gas cost can not be higher than the max gas fee cap value. If the maximum
      # allowed gas fee cap is reached, no further resubmission attempts are
      # performed. This property should be set only for Ethereum. In case of
      # legacy non-EIP-1559 transactions, this field works in the same way as
      # `MaxGasPrice` property.
      #
      # MaxGasFeeCap = "500 Gwei" # 500 Gwei (default value)

      # Uncomment to enable Ethereum node rate limiting. Both properties can be
      # used together or separately.
      #
      # RequestsPerSecondLimit sets the maximum average number of requests
      # per second which can be executed against the Ethereum node.
      # All types of Ethereum node requests are rate-limited,
      # including view function calls.
      #
      # RequestsPerSecondLimit = 150

      # ConcurrencyLimit sets the maximum number of concurrent requests which
      # can be executed against the Ethereum node at the same time.
      # This limit affects all types of Ethereum node requests,
      # including view function calls.
      #
      # ConcurrencyLimit = 30

      # BalanceAlertThreshold defines a minimum value of the operator's account
      # balance below which the client will start reporting errors in logs.
      # A value can be provided in `wei`, `Gwei` or `ether`, e.g. `7.5 ether`,
      # `7500000000 Gwei`.
      #
      # BalanceAlertThreshold = "0.5 ether" # 0.5 ether (default value)

      [bitcoin.electrum]
      # URL to the Electrum server in format: `scheme://hostname:port`.
      # Should be uncommented only when using a custom Electrum server. Otherwise,
      # one of the default embedded servers is selected randomly at startup.
      URL = "tcp://192.168.100.40:50001"

      # Timeout for a single attempt of Electrum connection establishment.
      # ConnectTimeout = "10s"

      # Timeout for Electrum connection establishment retries.
      # ConnectRetryTimeout = "1m"

      # Timeout for a single attempt of Electrum protocol request.
      # RequestTimeout = "30s"

      # Timeout for Electrum protocol request retries.
      # RequestRetryTimeout = "2m"

      # Interval for connection keep alive requests.
      # KeepAliveInterval = "5m"

      [network]
      Bootstrap = false
      Peers = [
        "/ip4/127.0.0.1/tcp/3919/ipfs/16Uiu2HAmFRJtCWfdXhZEZHWb4tUpH1QMMgzH1oiamCfUuK6NgqWX",
      ]
      Port = 3920

      # Uncomment to override the node's default addresses announced in the network
      AnnouncedAddresses = ["/dns4/hetzner-ephemeral-alpha.ponkila.com/tcp/3919"]

      # Uncomment to enable courtesy message dissemination for topics this node is
      # not subscribed to. Messages will be forwarded to peers for the duration
      # specified as a value in seconds.
      # Message dissemination is disabled by default and should be enabled only
      # on selected bootstrap nodes. It is not a good idea to enable dissemination
      # on non-bootstrap node as it may clutter communication and eventually lead
      # to blacklisting the node. The maximum allowed value is 90 seconds.
      #
      # DisseminationTime = 90

      [storage]
      Dir = "/var/mnt/keep-network"

      # ClientInfo exposes metrics and diagnostics modules.
      #
      # Metrics collects and exposes information useful for external monitoring tools usually
      # operating on time series data.
      # All values exposed by metrics module are quantifiable or countable.
      #
      # The following metrics are available:
      # - connected peers count
      # - connected bootstraps count
      # - eth client connectivity status
      #
      # Diagnostics module exposes the following information:
      # - list of connected peers along with their network id and ethereum operator address
      # - information about the client's network id and ethereum operator address
      [clientInfo]
      Port = 9601
      # NetworkMetricsTick = 60
      # EthereumMetricsTick = 600

      # Uncomment to overwrite default values for TBTC config.
      #
      # [tbtc]
      # PreParamsPoolSize = 3000
      # PreParamsGenerationTimeout = "2m"
      # PreParamsGenerationDelay = "10s"
      # PreParamsGenerationConcurrency = 1
      # KeyGenConcurrency = 1
    '';
  };
  systemd.services.keep-network = {
    enable = true;

    description = "keep-network bridge service";
    requires = ["blutgang.service" "nginx.service"];
    after = ["blutgang.service" "nginx.service"];

    serviceConfig = {
      EnvironmentFile = ''${config.sops.secrets."keep-network/env".path}'';
      Restart = "always";
      RestartSec = "5s";
      User = "core";
      Group = "core";
      Type = "simple";
    };

    script = ''      ${pkgs.keep-core}/bin/keep-core \
            start \
            -c /etc/keep-config.toml
    '';

    wantedBy = ["multi-user.target"];
  };

  services.nginx = {
    enable = true;
    config = ''
      events {
        worker_connections 1024;
      }

      stream {

        upstream bitcoin {
          server 192.168.100.10:50001;
          server 192.168.100.31:50001;
          server 192.168.100.32:50001;
        }

        server {
          listen 192.168.100.40:50001;
          proxy_pass bitcoin;
        }

      }
    '';
  };

  homestakeros = {
    # Localization options
    localization = {
      hostname = "hetzner-ephemeral-alpha";
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

    mounts = {
      blutgang = {
        enable = true;
        description = "blutgang store";

        what = "/dev/sda";
        where = "/var/mnt/blutgang";
        type = "btrfs";
        options = "subvolid=257";

        wantedBy = ["multi-user.target"];
      };
      keep-network = {
        enable = true;
        description = "keep-network store";

        what = "/dev/sda";
        where = "/var/mnt/keep-network";
        type = "btrfs";
        options = "subvolid=258";

        wantedBy = ["multi-user.target"];
      };
    };
  };

  # Secrets
  sops = {
    defaultSopsFile = ./secrets/default.yaml;
    secrets."wireguard/wg0" = {};
    secrets."keep-network/env" = {
      owner = "core";
      group = "core";
    };
    secrets."keep-network/operator-key" = {
      owner = "core";
      group = "core";
    };
    secrets."netdata/health_alarm_notify.conf" = {
      owner = "netdata";
      group = "netdata";
    };
    age.sshKeyPaths = [sshKeysPath];
  };

  networking.firewall = {
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

  services.netdata = {
    enable = true;
    configDir = {
      "health_alarm_notify.conf" = config.sops.secrets."netdata/health_alarm_notify.conf".path;
    };
  };

  system.stateVersion = "23.05";
}
