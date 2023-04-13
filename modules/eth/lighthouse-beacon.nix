
{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.lighthouse;
in {
  options.lighthouse = {
    enable = mkOption {
      type = types.bool;
      default = true;
    };
    endpoint = mkOption { 
      type = types.str; 
    };
    exec.endpoint = mkOption { 
      type = types.str; 
    };
    mev-boost = {
      endpoint = mkOption {
        type = types.str;
      };
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
      lighthouse
    ];

    # mount
    systemd.mounts = [
      {
        enable = true;

        description = "lighthouse storage";

        what = cfg.mount.source;
        where = cfg.mount.target;
        options = "noatime";
        type = "btrfs";

        wantedBy = [ "multi-user.target" ];
      }
    ];

    # service
    systemd.services.lighthouse = {
      enable = true;

      description = "beacon, mainnet";
      requires = [ "wg0.service" ];
      after = [ "wg0.service" "mev-boost.service" ];

      serviceConfig = {
        Restart = "always";
        RestartSec = "5s";
        User = "core";
        Group = "core";
        Type = "simple";
      };

      script = ''${pkgs.lighthouse}/bin/lighthouse bn \
        --datadir ${cfg.datadir} \
        --network mainnet \
        --http --http-address ${cfg.endpoint} \
        --execution-endpoint ${cfg.exec.endpoint} \
        --execution-jwt ${cfg.datadir}/jwt.hex \
        --builder ${cfg.mev-boost.endpoint} \
        --slasher --slasher-history-length 256 --slasher-max-db-size 16 \
        --prune-payloads false \
        --metrics
      '';

      wantedBy = [ "multi-user.target" ];
    };

    # firewall
    networking.firewall.interfaces."wg0".allowedTCPPorts = [
      5052 # lighthouse
    ];
  };
}