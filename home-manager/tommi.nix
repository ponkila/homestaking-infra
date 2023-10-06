{
  pkgs,
  config,
  inputs,
  lib,
  ...
}:
with lib; let
  cfg = config.users.tommi;
in {
  options.users.tommi = {
    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [];
    };
  };

  config = {
    users.users.tommi = {
      isNormalUser = true;
      group = "tommi";
      extraGroups = ["wheel" "users"];
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
      shell = pkgs.fish;
    };
    users.groups.tommi = {};
    environment.shells = [pkgs.fish];

    home-manager.users.tommi = {pkgs, ...}: {
      home.stateVersion = "23.05";

      programs.nix-index.enable = true;
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      programs.htop.enable = true;

      programs.fish = {
        enable = true;
      };

      programs.git = {
        enable = true;
      };
    };
  };
}
