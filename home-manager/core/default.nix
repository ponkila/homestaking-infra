
{ pkgs, config, inputs, lib, ... }:
{
home-manager.users.core = { pkgs, ... }: {

    sops = {
      defaultSopsFile = ./secrets/default.yaml;
      secrets."wireguard/wg0" = {
        path = "%r/wireguard/wg0.conf";
      };
      age.sshKeyPaths = [ "/var/mnt/secrets/ssh/id_ed25519" ];
    };

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
}