{ pkgs, config, inputs, lib, ... }:
with lib;
let
  cfg = config.users.allu;
in
{
  options.users.allu = {
    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
  };

  config = {
    users.users.allu = {
      isNormalUser = true;
      group = "allu";
      extraGroups = [ "wheel" "users" ];
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
      shell = pkgs.fish;
    };
    users.groups.allu = { };
    environment.shells = [ pkgs.fish ];

    home-manager.users.allu = { pkgs, ... }: {

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
