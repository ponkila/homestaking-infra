{ pkgs, config, inputs, lib, ... }:
{
  # User options
  users = {
    juuso.authorizedKeys = [ "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local" ];
    kari.authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque" ];
  };

  # Users group
  users.groups.users = { };

  # Localization
  networking.hostName = "hetzner-ephemeral-beta";
  time.timeZone = "Europe/Helsinki";

  # Apply kernel personality patch from Ubuntu and configure armv7l support
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

  # Hercules CI
  services.hercules-ci-agent = {
    enable = true;
    settings.baseDirectory = "/var/mnt/.config/hercules-ci-agent";
  };

  systemd.mounts = [
    {
      enable = true;

      what = "/dev/disk/by-label/nix";
      where = "/var/mnt/.config";
      type = "btrfs";
      options = "subvolid=257";

      before = [ "hercules-ci-agent.service" ];
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
      AllowAgentForwarding no
      AllowStreamLocalForwarding no
      AuthenticationMethods publickey
    '';
    settings.PasswordAuthentication = false;
    settings.challengeResponseAuthentication = false;
  };

  system.stateVersion = "23.05";
}
