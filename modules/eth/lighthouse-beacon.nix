{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.lighthouse;
in
{
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
    slasher = {
      enable = mkOption {
        type = types.bool;
      };
      history-length = mkOption {
        type = types.int;
        default = 4096;
      };
      max-db-size = mkOption {
        type = types.int;
        default = 256;
      };
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
      type = mkOption { type = types.str; };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # only execute this if cfg.mounts are set
    (mkIf cfg.mounts {
      systemd.mounts = [
        {
          enable = true;

          description = "lighthouse storage";

          what = cfg.mount.source;
          where = cfg.mount.target;
          options = lib.mkDefault "noatime";
          type = cfg.mount.type;

          wantedBy = [ "multi-user.target" ];
        }
      ];
    })
    # always execute this
    (mkIf cfg.enable {
      # package
      environment.systemPackages = with pkgs; [
        lighthouse
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
          --prune-payloads false \
          --metrics \
          ${if cfg.slasher.enable then
            "--slasher "
            + " --slasher-history-length " + (toString cfg.slasher.history-length)
            + " --slasher-max-db-size " + (toString cfg.slasher.max-db-size)
          else "" }
        '';
        wantedBy = [ "multi-user.target" ];
      };

      # firewall
      networking.firewall = {
        allowedTCPPorts = [ 9000 ];
        allowedUDPPorts = [ 9000 ];
        interfaces."wg0".allowedTCPPorts = [
          5052 # lighthouse
        ];
      };
    })
  ]);
}
