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

  boot.kernelParams = [
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
  boot.kernelPackages = lib.mkDefault (pkgs.linuxPackagesFor (pkgs.linux_latest));

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
        color = "red";
        command = ''
          ${pkgs.nettools}/bin/hostname | ${pkgs.figlet}/bin/figlet -f slant
          systemctl --failed --quiet
        '';
      };
      last_login = builtins.listToAttrs (map
        (user: {
          name = user;
          value = 2;
        })
        builtins.attrNames config.home-manager.users);
    };
  };

  services.timesyncd.enable = false;
  services.chrony = {
    enable = true;
    servers = [
      "ntp1.hetzner.de"
      "ntp2.hetzner.com"
      "ntp3.hetzner.net"
    ];
  };

  systemd.watchdog.device = "/dev/watchdog";
  systemd.watchdog.runtimeTime = "30s";

  # Audit Tracing
  security.auditd.enable = true;
  security.audit.enable = true;
  security.audit.rules = [
    "-a exit,always -F arch=b64 -S execve"
  ];

  # Rip Out Default Packages
  environment.defaultPackages = lib.mkForce [ ];

  # Allow passwordless sudo from wheel group
  security.sudo = {
    enable = lib.mkDefault true;
    wheelNeedsPassword = lib.mkForce false;
    execWheelOnly = true;
  };
}
