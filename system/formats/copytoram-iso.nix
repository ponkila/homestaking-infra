# derived from https://github.com/nix-community/nixos-generators/blob/master/formats/install-iso.nix
{ config, lib, modulesPath, ... }:
{
  imports = [
    "${toString modulesPath}/installer/cd-dvd/installation-cd-base.nix"
  ];

  # for installer
  isoImage.isoName = lib.mkForce "nixos.iso";

  # override installation-cd-base and enable wpa and sshd start at boot
  #systemd.services.wpa_supplicant.wantedBy = lib.mkForce [ "multi-user.target" ];
  #systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

  # GRUB timeout
  boot.loader.timeout = lib.mkForce 1;

  # Load into a tmpfs during stage-1
  boot.kernelParams = [ "copytoram" ];
}
