{ pkgs, config, inputs, lib, ... }:

let
  infra.ip = "192.168.100.10";

  eth1.endpoint = infra.ip;
  eth1.datadir = "/var/mnt/erigon";

  eth2.endpoint = infra.ip;
  eth2.datadir = "/var/mnt/lighthouse";

  mev-boost.endpoint = infra.ip;
in
{

  home-manager.users.core = { pkgs, ... }: {

    sops = {
      defaultSopsFile = ./secrets/default.yaml;
      secrets."wireguard/wg0" = {
        path = "%r/wireguard/wg0.conf";
      };
      age.sshKeyPaths = [ "/var/mnt/secrets/ssh/id_ed25519" ];
    };

    home.packages = with pkgs; [
      file
      tree
      bind # nslookup
    ];

    programs = {
      tmux.enable = true;
      htop.enable = true;
      vim.enable = true;
      git.enable = true;
      fish.enable = true;
      fish.loginShellInit = "fish_add_path --move --prepend --path $HOME/.nix-profile/bin /run/wrappers/bin /etc/profiles/per-user/$USER/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin";

      home-manager.enable = true;
    };

    home.stateVersion = "23.05";
  };

  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Deduplicate and optimize nix store
      auto-optimise-store = true;
      # Allows this server to be used as a remote builder
      trusted-users = [
        "root"
        "@wheel"
      ];

    };

    package = pkgs.nix;
  };

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
  ];

  networking.hostName = "ponkila-ephemeral-beta";
  time.timeZone = "Europe/Helsinki";

  boot.kernelParams = [
    "mitigations=off"
    "l1tf=off"
    "mds=off"
    "no_stf_barrier"
    "noibpb"
    "noibrs"
    "nopti"
    "nospec_store_bypass_disable"
    "nospectre_v1"
    "nospectre_v2"
    "tsx=on"
    "tsx_async_abort=off"
  ];
  boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.linux_latest);

  ## Allow passwordless sudo from nixos user
  security.sudo = {
    enable = lib.mkDefault true;
    wheelNeedsPassword = lib.mkForce false;
  };
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    hostKeys = [{
      path = "/var/mnt/secrets/ssh/id_ed25519";
      type = "ed25519";
    }];
  };

  environment.systemPackages = with pkgs; [
    btrfs-progs
    kexec-tools
    fuse-overlayfs

    lighthouse
    erigon
  ];

  services.timesyncd.enable = false;
  services.chrony = {
    enable = true;
    servers = [
      "ntp1.hetzner.de"
      "ntp2.hetzner.com"
      "ntp3.hetzner.net"
    ];
  };

  networking.firewall.interfaces."wg0".allowedTCPPorts = [
    5052 # lighthouse
  ];
  networking.firewall = {
    allowedTCPPorts = [ 30303 30304 42069 9000 ];
    allowedUDPPorts = [ 30303 30304 42069 9000 ];
  };

  systemd.watchdog.device = "/dev/watchdog";
  systemd.watchdog.runtimeTime = "30s";

  systemd.mounts = [
    {
      enable = true;

      description = "lighthouse storage";

      what = "/dev/disk/by-label/lighthouse";
      where = "/var/mnt/lighthouse";
      options = "noatime";
      type = "btrfs";

      wantedBy = [ "multi-user.target" ];
    }
    {
      enable = true;

      description = "erigon storage";

      what = "/dev/disk/by-label/erigon";
      where = "/var/mnt/erigon";
      options = "noatime";
      type = "btrfs";

      wantedBy = [ "multi-user.target" ];
    }
    {
      enable = true;

      description = "testnet storage";

      what = "/dev/disk/by-label/testnets";
      where = "/var/mnt/testnets";
      options = "noatime";
      type = "btrfs";

      wantedBy = [ "multi-user.target" ];
    }
    {
      enable = true;

      description = "secrets storage";

      what = "/dev/disk/by-label/secrets";
      where = "/var/mnt/secrets";
      type = "btrfs";

      before = [ "sops-nix.service" "sshd.service" ];
      wantedBy = [ "multi-user.target" ];
    }
  ];

  systemd.services.wg0 = {
    enable = true;

    description = "wireguard interface for cross-node communication";
    requires = [ "network-online.target" ];
    after = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
    };

    script = ''${pkgs.wireguard-tools}/bin/wg-quick \
      up /run/user/1000/wireguard/wg0.conf
    '';

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.erigon = {
    enable = true;

    description = "execution, mainnet";
    requires = [ "wg0.service" ];
    after = [ "wg0.service" "lighthouse.service" ];

    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
      User = "core";
      Group = "core";
      Type = "simple";
    };

    script = ''${pkgs.erigon}/bin/erigon \
      --datadir=${eth1.datadir} \
      --chain mainnet \
      --authrpc.vhosts="*" \
      --authrpc.addr ${infra.ip} \
      --authrpc.jwtsecret=${eth1.datadir}/jwt.hex \
      --metrics \
      --externalcl
    '';

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.lighthouse = {
    enable = true;

    description = "beacon, mainnet";
    requires = [ "wg0.service" ];
    after = [ "wg0.service" "mev-boost.service" ];

    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
      User = "core";
      Group = "core";
      Type = "simple";
    };

    script = ''${pkgs.lighthouse}/bin/lighthouse bn \
      --datadir ${eth2.datadir} \
      --network mainnet \
      --http --http-address ${infra.ip} \
      --execution-endpoint http://${eth1.endpoint}:8551 \
      --execution-jwt ${eth2.datadir}/jwt.hex \
      --builder http://${mev-boost.endpoint}:18550 \
      --slasher --slasher-history-length 256 --slasher-max-db-size 16 \
      --prune-payloads false \
      --metrics
    '';

    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.podman.enable = true;
  # dnsname allows containers to use ${name}.dns.podman to reach each other
  # on the same host instead of using hard-coded IPs.
  # NOTE: --net must be the same on the containers, and not eq "host"
  # TODO: extend this with flannel ontop of wireguard for cross-node comms
  virtualisation.podman.defaultNetwork.settings.dns_enabled = true;

  systemd.services.linger = {
    enable = true;

    requires = [ "local-fs.target" ];
    after = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        /run/current-system/sw/bin/loginctl enable-linger core
      '';
    };

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.mev-boost = {
    path = [ "/run/wrappers" ];
    enable = true;

    description = "MEV-boost allows proof-of-stake Ethereum consensus clients to outsource block construction";
    requires = [ "wg0.service" ];
    after = [ "wg0.service" ];

    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
      User = "core";
      Group = "core";
      Type = "simple";
    };

    preStart = "${pkgs.podman}/bin/podman stop mev-boost || true";
    script = ''${pkgs.podman}/bin/podman \
      --storage-opt "overlay.mount_program=${pkgs.fuse-overlayfs}/bin/fuse-overlayfs" run \
      --replace --rmi \
      --name mev-boost \
      -p 18550:18550 \
      docker.io/flashbots/mev-boost:latest \
      -mainnet \
      -relay-check \
      -relays ${lib.concatStringsSep "," [
        "https://0xac6e77dfe25ecd6110b8e780608cce0dab71fdd5ebea22a16c0205200f2f8e2e3ad3b71d3499c54ad14d6c21b41a37ae@boost-relay.flashbots.net"
        "https://0xad0a8bb54565c2211cee576363f3a347089d2f07cf72679d16911d740262694cadb62d7fd7483f27afd714ca0f1b9118@bloxroute.ethical.blxrbdn.com"
        "https://0x9000009807ed12c1f08bf4e81c6da3ba8e3fc3d953898ce0102433094e5f22f21102ec057841fcb81978ed1ea0fa8246@builder-relay-mainnet.blocknative.com"
        "https://0xb0b07cd0abef743db4260b0ed50619cf6ad4d82064cb4fbec9d3ec530f7c5e6793d9f286c4e082c0244ffb9f2658fe88@bloxroute.regulated.blxrbdn.com"
        "https://0x8b5d2e73e2a3a55c6c87b8b6eb92e0149a125c852751db1422fa951e42a09b82c142c3ea98d0d9930b056a3bc9896b8f@bloxroute.max-profit.blxrbdn.com"
        "https://0x98650451ba02064f7b000f5768cf0cf4d4e492317d82871bdc87ef841a0743f69f0f1eea11168503240ac35d101c9135@mainnet-relay.securerpc.com"
        "https://0x84e78cb2ad883861c9eeeb7d1b22a8e02332637448f84144e245d20dff1eb97d7abdde96d4e7f80934e5554e11915c56@relayooor.wtf"
      ]} \
      -addr 0.0.0.0:18550
  '';

    wantedBy = [ "multi-user.target" ];
  };

  services.prometheus = {
    enable = false;
    port = 9001;
    exporters = {
      node = {
        enable = false;
        enabledCollectors = [ "systemd" ];
        port = 9002;
      };
    };
    scrapeConfigs = [
      {
        job_name = config.networking.hostName;
        static_configs = [{
          targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
        }];
      }
      {
        job_name = "erigon";
        metrics_path = "/debug/metrics/prometheus";
        scheme = "http";
        static_configs = [{
          targets = [ "127.0.0.1:6060" "127.0.0.1:6061" "127.0.0.1:6062" ];
        }];
      }
      {
        job_name = "lighthouse";
        scrape_interval = "5s";
        static_configs = [{
          targets = [ "127.0.0.1:5054" "127.0.0.1:5064" ];
        }];
      }
    ];
  };
  system.stateVersion = "23.05";
}
