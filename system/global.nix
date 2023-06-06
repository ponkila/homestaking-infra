{ pkgs, config, lib, inputs, ... }:
{
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

  boot = {
    kernelParams = [
      "boot.shell_on_fail"

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
    kernelPackages = lib.mkDefault (pkgs.linuxPackagesFor (pkgs.linux_latest));
  } // (
    # Increase tmpfs (default: "50%")
    if (lib.trivial.release == "22.11") then {
      tmpOnTmpfsSize = "80%";
    } else {
      tmp.tmpfsSize = "80%";
    }
  );

  environment.systemPackages = with pkgs; [
    btrfs-progs
    kexec-tools
    fuse-overlayfs
  ];

  programs.rust-motd = {
    enable = true;
    enableMotdInSSHD = true;
    settings = {
      banner = {
        color = "yellow";
        command = ''
          echo ""
          echo " +-------------+"
          echo " | 10110 010   |"
          echo " | 101 101 10  |"
          echo " | 0   _____   |"
          echo " |    / ___ \  |"
          echo " |   / /__/ /  |"
          echo " +--/ _____/---+"
          echo "   / /"
          echo "  /_/"
          echo ""
          systemctl --failed --quiet
        '';
      };
      uptime.prefix = "Uptime:";
      last_login = builtins.listToAttrs (map
        (user: {
          name = user;
          value = 2;
        })
        (builtins.attrNames config.home-manager.users));
    };
  };

  # Better clock sync via chrony
  services.timesyncd.enable = false;
  services.chrony = {
    enable = true;
    servers = [
      "ntp1.hetzner.de"
      "ntp2.hetzner.com"
      "ntp3.hetzner.net"
    ];
  };

  # Enable podman with DNS
  virtualisation.podman = {
    enable = true;
  } // (
    # dnsname allows containers to use ${name}.dns.podman to reach each other
    # on the same host instead of using hard-coded IPs.
    # NOTE: --net must be the same on the containers, and not eq "host"
    # TODO: extend this with flannel ontop of wireguard for cross-node comms
    if (lib.trivial.release == "22.11") then {
      defaultNetwork.dnsname.enable = true;
    } else {
      defaultNetwork.settings = { dns_enabled = true; };
    }
  );

  # Reboots hanged system
  systemd.watchdog.device = "/dev/watchdog";
  systemd.watchdog.runtimeTime = "30s";

  # Zram swap
  zramSwap.enable = true;
  zramSwap.algorithm = "zstd";
  zramSwap.memoryPercent = 100;

  # Audit tracing
  security.auditd.enable = true;
  security.audit.enable = true;
  security.audit.rules = [
    "-a exit,always -F arch=b64 -S execve"
  ];

  # Rip out packages
  environment.defaultPackages = lib.mkForce [ ];
  environment.noXlibs = true;
  documentation.doc.enable = false;
  xdg.mime.enable = false;
  xdg.menus.enable = false;
  xdg.icons.enable = false;
  xdg.sounds.enable = false;
  xdg.autostart.enable = false;

  # Allow passwordless sudo from wheel group
  security.sudo = {
    enable = lib.mkDefault true;
    wheelNeedsPassword = lib.mkForce false;
    execWheelOnly = true;
  };
}
