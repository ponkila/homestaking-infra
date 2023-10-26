{
  pkgs,
  config,
  inputs,
  lib,
  ...
}: {
  homestakeros = {
    # Localization options
    localization = {
      hostname = "ponkila-ephemeral-gamma";
      timezone = "Europe/Helsinki";
    };

    # SSH options
    ssh = {
      authorizedKeys = [
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNMKgTTpGSvPG4p8pRUWg1kqnP9zPKybTHQ0+Q/noY5+M6uOxkLy7FqUIEFUT9ZS/fflLlC/AlJsFBU212UzobA= ssh@secretive.sandbox.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEdpdbTOz0h9tVvkn13k1e8X7MnctH3zHRFmYWTbz9T kari@torque"
      ];
    };
  };

  # Use RPi4 kernel
  boot.kernelPackages = pkgs.linuxPackages_rpi4;

  system.stateVersion = "23.05";
}
