# derived from https://github.com/nix-community/nixos-generators/blob/master/formats/iso.nix

{ config, lib, modulesPath, ... }:
{
  imports = [
    "${toString modulesPath}/installer/cd-dvd/iso-image.nix"
  ];

  # GRUB timeout
  boot.loader.timeout = lib.mkForce 1;
  
  # Load into a tmpfs during stage-1
  boot.kernelParams = [ "copytoram" ];
  
  # EFI & USB booting
  isoImage = {
    makeEfiBootable = true;
    makeUsbBootable = true;
  };
}
