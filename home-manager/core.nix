{ pkgs, config, inputs, lib, ... }:
with lib;
let
  cfg = config.user;
in
{
  options.user = {
    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
  };

  config = {
    users.users.core = {
      isNormalUser = true;
      group = "core";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
      #shell = pkgs.fish;
    };
    users.groups.core = { };
    #environment.shells = [ pkgs.fish ];
    #programs.fish.enable = true;

    home-manager.users.core = { pkgs, ... }: {

      home.packages = with pkgs; [
        file
        tree
        bind # nslookup
      ];

      programs = {
        tmux.enable = true;
        htop.enable = true;
        vim.enable = true;
        git.enable = true;
        #fish.enable = true;
        #fish.loginShellInit = "fish_add_path --move --prepend --path $HOME/.nix-profile/bin /run/wrappers/bin /etc/profiles/per-user/$USER/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin";

        home-manager.enable = true;
      };

      home.stateVersion = "23.05";
    };
  };
}
