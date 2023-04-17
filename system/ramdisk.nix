{ config
, lib
, ...
}:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [
    # netboot
    "overlay"
    "squashfs"

    # kvm
    "9p"
    "9pnet_virtio"
    "virtio_blk"
    "virtio_mmio"
    "virtio_net"
    "virtio_pci"
    "virtio_scsi"
  ];
  boot.initrd.kernelModules = [
    # netboot
    "loop"
    "overlay"

    # kvm
    "virtio_balloon"
    "virtio_console"
    "virtio_rng"
  ];

  fileSystems."/" = lib.mkImageMediaOverride {
    fsType = "tmpfs";
    options = [ "mode=0755" ];
  };

  # In stage 1, mount a tmpfs on top of /nix/store (the squashfs
  # image) to make this a live CD.
  fileSystems."/nix/.ro-store" = lib.mkImageMediaOverride {
    fsType = "squashfs";
    device = "../nix-store.squashfs";
    options = [ "loop" ];
    neededForBoot = true;
  };

  fileSystems."/nix/.rw-store" = lib.mkImageMediaOverride {
    fsType = "tmpfs";
    options = [ "mode=0755" ];
    neededForBoot = true;
  };

  fileSystems."/nix/store" = lib.mkImageMediaOverride {
    fsType = "overlay";
    device = "overlay";
    options = [
      "lowerdir=/nix/.ro-store"
      "upperdir=/nix/.rw-store/store"
      "workdir=/nix/.rw-store/work"
    ];

    depends = [
      "/nix/.ro-store"
      "/nix/.rw-store/store"
      "/nix/.rw-store/work"
    ];
  };

  boot.postBootCommands =
    ''
      # After booting, register the contents of the Nix store in the Nix database in the tmpfs.
      ${config.nix.package}/bin/nix-store --load-db < /nix/store/nix-path-registration
      # nixos-rebuild also requires a "system" profile and an /etc/NIXOS tag.
      touch /etc/NIXOS
      ${config.nix.package}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
    '';
}
