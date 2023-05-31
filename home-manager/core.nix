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
    services.getty.autologinUser = "core";
    users.users.core = {
      isNormalUser = true;
      group = "core";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
      shell = pkgs.fish;
    };
    users.groups.core = { };
    environment.shells = [ pkgs.fish ];
    programs.fish.enable = true;

    home-manager.users.root.home.stateVersion = config.home-manager.users.core.home.stateVersion;
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
        fish.enable = true;
        fish.loginShellInit = "fish_add_path --move --prepend --path $HOME/.nix-profile/bin /run/wrappers/bin /etc/profiles/per-user/$USER/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin";

        home-manager.enable = true;
      };

      home.stateVersion = "23.05";
    };

    systemd.services.wg0 = {
      enable = true;

      description = "wireguard interface for cross-node communication";
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
      };

      preStart = "${pkgs.wireguard-tools}/bin/wg-quick down %r/wireguard/wg0.conf || true";
      script = ''${pkgs.wireguard-tools}/bin/wg-quick \
        up %r/wireguard/wg0.conf
      '';

      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.linger = {
      enable = true;

      requires = [ "local-fs.target" ];
      after = [ "local-fs.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = ''
          /run/current-system/sw/bin/loginctl enable-linger core
        '';
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
