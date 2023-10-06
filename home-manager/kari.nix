{
  pkgs,
  config,
  inputs,
  lib,
  ...
}:
with lib; let
  cfg = config.users.kari;
in {
  options.users.kari = {
    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [];
    };
  };

  config = {
    users.users.kari = {
      isNormalUser = true;
      group = "kari";
      extraGroups = ["wheel" "users"];
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
      shell = pkgs.fish;
    };
    users.groups.kari = {};
    environment.shells = [pkgs.fish];

    programs = {
      neovim = {
        enable = true;
      };

      fish = {
        enable = true;
        vendor = {
          completions.enable = true;
          config.enable = true;
          functions.enable = true;
        };
      };
    };

    # Home-manager
    home-manager.users.root.home.stateVersion = config.home-manager.users.kari.home.stateVersion;
    home-manager.users.kari = {
      home.stateVersion = "23.05";

      home.packages = with pkgs; [
        exa
        gnupg
        rsync
      ];

      programs.fish = {
        enable = true;
        shellAbbrs = rec {
          q = "exit";
          c = "clear";
          ka = "killall";
          vim = "nvim";
          ls = "exa -al --color=always --group-directories-first";
          tree = "exa -T";
          rcp = "rsync -PaL";
          rmv = "rsync -PaL --remove-source-files";
          jctl = "journalctl -p 3 -xb";
        };
        functions = {fish_greeting = "";};
        interactiveShellInit =
          ''
            set -x EDITOR nvim
          ''
          +
          # Use vim bindings and cursors
          ''
            fish_vi_key_bindings
            set fish_cursor_default     block      blink
            set fish_cursor_insert      line       blink
            set fish_cursor_replace_one underscore blink
            set fish_cursor_visual      block
          '';
      };

      programs = {
        tmux.enable = true;
        htop.enable = true;
        vim.enable = true;
        git.enable = true;
        direnv = {
          enable = true;
          nix-direnv.enable = true;
        };

        home-manager.enable = true;
      };
    };
  };
}
