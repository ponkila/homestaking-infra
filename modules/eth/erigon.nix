
{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.erigon;
in {
  options.erigon = {
    enable = mkOption {
      type = types.bool;
      default = true;
    };
    endpoint = mkOption { 
      type = types.str; 
    };
    datadir = mkOption { 
      type = types.str; 
    };
    mount = {
      source = mkOption { type = types.str; };
      target = mkOption { type = types.str; };
    };
  };

  config = mkIf cfg.enable {
    # package
    environment.systemPackages = with pkgs; [
      erigon
    ];

    # mount
    systemd.mounts = [
      {
        enable = true;

        description = "erigon storage";

        what = cfg.mount.source;
        where = cfg.mount.target;
        options = "noatime";
        type = "btrfs";

        wantedBy = [ "multi-user.target" ];
      }
    ];

    # service
    systemd.services.erigon = {
      enable = true;

      description = "execution, mainnet";
      requires = [ "wg0.service" ];
      after = [ "wg0.service" "lighthouse.service" ];

      serviceConfig = {
        Restart = "always";
        RestartSec = "5s";
        User = "core";
        Group = "core";
        Type = "simple";
      };

      script = ''${pkgs.erigon}/bin/erigon \
        --datadir=${cfg.datadir} \
        --chain mainnet \
        --authrpc.vhosts="*" \
        --authrpc.addr ${cfg.endpoint} \
        --authrpc.jwtsecret=${cfg.datadir}/jwt.hex \
        --metrics \
        --externalcl
      '';

      wantedBy = [ "multi-user.target" ];
    };
  };
}