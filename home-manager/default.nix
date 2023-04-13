
{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.user;
in {
  # auto import user's home-manager env
  imports = [ ./core/default.nix ];

  options.user = {
    name = mkOption {
      type = types.str;
    };
    shell = mkOption {
      type = types.str; 
      default = "fish";
    };
    authorizedKeys = mkOption {
      type =  types.listOf types.str;
      default = [];
    };
  };

  config = {
    users.users.${cfg.name} = {
      isNormalUser = true;
      group = cfg.name;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
      shell = pkgs.${cfg.shell};
    };
    users.groups.${cfg.name} = { };
    environment.shells = [ pkgs.${cfg.shell} ];
    programs.${cfg.shell}.enable = true;
  };
}