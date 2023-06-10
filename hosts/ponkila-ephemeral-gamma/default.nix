{ pkgs, config, inputs, lib, ... }:
{
  # User options
  users = {
    juuso.authorizedKeys = [ "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local" ];
    kari.authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque" ];
  };

  # Localization
  networking.hostName = "ponkila-ephemeral-gamma";
  time.timeZone = "Europe/Helsinki";

  # Use RPi4 kernel
  boot.kernelPackages = pkgs.linuxPackages_rpi4;

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
    passwordAuthentication = false;
    kbdInteractiveAuthentication = false;
  };

  system.stateVersion = "23.05";
}
