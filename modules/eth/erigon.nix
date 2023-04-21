{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.erigon;
in
{
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
      type = mkOption { type = types.str; };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # package
    environment.systemPackages = with pkgs; [
      erigon
    ];

    # only execute this if cfg.mounts are set
    (mkIf cfg.mounts {
      systemd.mounts = [
        {
          enable = true;

          description = "erigon storage";

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

      # firewall
      networking.firewall = {
        allowedTCPPorts = [ 30303 30304 42069 ];
        allowedUDPPorts = [ 30303 30304 42069 ];
      };
    })
  ]);
}
