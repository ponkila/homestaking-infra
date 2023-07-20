{ pkgs, config, inputs, lib, ... }:
let
  sshKeysPath = "/var/mnt/secrets/ssh/id_ed25519";
in
{
  # User options
  users = {
    juuso.authorizedKeys = [ "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local" ];
    kari.authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque" ];
  };

  # Users group
  users.groups.users = { };

  # Localization
  networking.hostName = "hetzner-ephemeral-alpha";
  time.timeZone = "Europe/Helsinki";

  # Support for cross compilation
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
  ];

  # Saiko's automatic gc
  sys2x.gc.useDiskAware = true;

  systemd.mounts = [
    {
      enable = true;

      what = "/dev/disk/by-label/nix";
      where = "/var/mnt/secrets";
      type = "btrfs";
      options = "subvolid=261";

      wantedBy = [ "multi-user.target" ];
    }
  ];

  systemd.services.nix-remount = {
    path = [ "/run/wrappers" ];
    enable = true;

    serviceConfig = {
      Type = "oneshot";
    };

    # if a new device, the new .rw-store has to be mounted
    preStart = ''
      /run/wrappers/bin/mount /dev/disk/by-label/nix -o subvolid=256 /nix/.rw-store
      mkdir -p /nix/.rw-store/work
      mkdir -p /nix/.rw-store/store
    '';
    script = ''
      /run/wrappers/bin/mount -t overlay overlay -o lowerdir=/nix/.ro-store:/nix/store,upperdir=/nix/.rw-store/store,workdir=/nix/.rw-store/work /nix/store
    '';

    wantedBy = [ "multi-user.target" ];
  };

  # SSH
  services.openssh = {
    enable = true;
    allowSFTP = false;
    hostKeys = [{
      path = sshKeysPath;
      type = "ed25519";
    }];
    extraConfig = ''
      AllowTcpForwarding yes
      X11Forwarding no
      AllowAgentForwarding no
      AllowStreamLocalForwarding no
      AuthenticationMethods publickey
    '';
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };

  # MOTD
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

  # Secrets
  sops = {
    secrets."cache-server/private-key" = {
      sopsFile = ./secrets/default.yaml;
    };
    age.sshKeyPaths = [ sshKeysPath ];
  };

  # Binary cache server
  services.nix-serve = {
    enable = true;
    secretKeyFile = config.sops.secrets."cache-server/private-key".path;
  };

  # Web server
  networking.firewall.allowedTCPPorts = [ 80 ];
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts = {
      "buidl0.ponkila.com" = {
        # Redirecting the HTTP traffic from port 80 to 'nix-serve' which operates on port 5000 by default
        locations."/".proxyPass = "http://${config.services.nix-serve.bindAddress}:${toString config.services.nix-serve.port}";
      };
    };
  };

  system.stateVersion = "23.05";
}
