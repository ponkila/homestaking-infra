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

    "dm_mod"
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
      do_clear = true
      address = "192.168.100.40:8545"
      # Moving average length for the latency
      ma_length = 10
      # Sort RPCs by latency on startup. Recommended to leave on.
      sort_on_startup = true
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
      enabled = true
      address = "127.0.0.1:5715"
      readonly = false
      # Enable the use of JWT for auth
      # Should be on if exposing to the internet
      jwt = false
      # jwt token
      key = ""

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
      max_consecutive = 5
      max_per_second = 0

      [dinar-ephemeral-alpha]
      url = "http://192.168.100.31:8545"
      ws_url = "ws://192.168.100.31:8546"
      max_consecutive = 5
      max_per_second = 0

      [majbacka-persistent-alpha]
      url = "http://192.168.100.21:8545"
      ws_url = "ws://192.168.100.21:8546"
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

    script = ''      /var/mnt/blutgang-0.3.0/bin/blutgang \
            -c /etc/blutgang.toml
    '';

    wantedBy = ["multi-user.target"];
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

    script = ''      /var/mnt/keep-core/keep-client \
            start \
            --ethereum.url ws://192.168.100.40:8545 \
            --ethereum.keyFile /run/secrets/keep-network/operator-key \
            --bitcoin.electrum.url tcp://192.168.100.40:50001 \
            --storage.dir /var/mnt/keep-network
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
        }

        server {
          listen 192.168.100.40:50001;
          proxy_pass bitcoin;
        }

      }
    '';
  };
  systemd.services.nginx.requires = ["wg-quick-wg0.service"];
  systemd.services.nginx.after = ["wg-quick-wg0.service"];

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
