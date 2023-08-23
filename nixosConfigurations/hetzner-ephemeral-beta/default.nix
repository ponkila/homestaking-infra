{ pkgs, config, inputs, lib, ... }:
{
  # User options
  users = {
    juuso.authorizedKeys = [ "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local" ];
    kari.authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque" ];
    allu.authorizedKeys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCkfHIgiK8S5awFn+oOdduS2mp5UGT4ki/ndoMArBol1dvRSKAdHS4okCX/umiy4BqAsDFkpYWuwe897NdOosba0iVyrFsYRou9FrOnQIMRIgtAvaOXeo2U4432glzH4WsMD+D+F4wHZ7walsrkaIPihpoHtWp8DkTPcFm1D8GP1o5TNpTjSFSuPFSzC2nburVcyfxZJluh/hxnxtYLNrmwOOHLhXcTmy5rQQ5u2HI5y64tS6fnKxxozA2gPaVro5+W5e3WtpSDGdd2NkPDzrMMmwYFEv4Tw9ooUfaJhXhq7AJakK/nTfpLquL9XSia8af+aOzx/p1v25f56dESlhNzcSlREP52hTA9T3foCA2IBkDitBeeGhUeeerQdczoRFxxSjoI244bPwAZ+tKIwO0XFaxLyd3jjzlya0F9w1N7wN0ZO4hY1NVv7oaYTUcU7TnvqGEMGLZpQBnIn7DCrUjKeW4AIUGvxcCP+F16lqFkuLSCgOAHM59NECVwBAOPGDk=" ];
    tommi.authorizedKeys = [
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAID5aw7sqJrXdKdNVu9IAyCCw1OYHXFQmFu/s/K+GAmGfAAAABHNzaDo= da@pusu"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINwWpZR5WuzyJlr7jYoe0mAYp+MJ12doozfqGz9/8NP/AAAABHNzaDo= da@pusu"
    ];
  };

  # Users group
  users.groups.users = { };

  # Localization
  networking.hostName = "hetzner-ephemeral-beta";
  time.timeZone = "Europe/Helsinki";

  # Use stable kernel
  boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.linux);

  # Saiko's automatic gc
  sys2x.gc.useDiskAware = true;

  # Apply kernel personality patch from Ubuntu and configure armv7l support
  # https://github.com/nix-community/aarch64-build-box/pull/133
  boot.kernelPatches = [
    rec {
      name = "compat_uts_machine";
      patch = pkgs.fetchpatch {
        inherit name;
        url = "https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/jammy/patch/?id=c1da50fa6eddad313360249cadcd4905ac9f82ea";
        sha256 = "sha256-mpq4YLhobWGs+TRKjIjoe5uDiYLVlimqWUCBGFH/zzU=";
      };
    }
  ];
  boot.kernelParams = [
    "compat_uts_machine=armv7l"
  ];
  nix.extraOptions = "extra-platforms = armv7l-linux";

  systemd.mounts = [
    {
      enable = true;

      what = "/dev/disk/by-label/nix";
      where = "/var/mnt/secrets";
      type = "btrfs";
      options = "subvolid=258";

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
      /run/wrappers/bin/mount /dev/disk/by-label/nix -o subvolid=257 /nix/.rw-store
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
    extraConfig = ''
      AllowTcpForwarding yes
      X11Forwarding no
      #AllowAgentForwarding no
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

  # Binary cache
  services.nix-serve = {
    enable = true;
    secretKeyFile = "/var/mnt/secrets/cache-server/cache-priv-key.pem";
    port = 5000;
    openFirewall = true;
  };

  system.stateVersion = "23.05";
}
