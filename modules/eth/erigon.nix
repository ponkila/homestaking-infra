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
  };

  config = mkIf cfg.enable {
    # package
    environment.systemPackages = with pkgs; [
      erigon
    ];

    # service
    systemd.user.services.erigon = {
      enable = true;

      description = "execution, mainnet";
      requires = [ "wg0.service" ];
      after = [ "wg0.service" "lighthouse.service" ];

      serviceConfig = {
        Restart = "always";
        RestartSec = "5s";
        Type = "simple";
      };

      script = ''${pkgs.erigon}/bin/erigon \
        --datadir=${cfg.datadir} \
        --chain mainnet \
        --authrpc.vhosts="*" \
        --authrpc.addr ${cfg.endpoint} \
        --authrpc.jwtsecret=%r/jwt.hex \
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

    # firewall
    networking.firewall = {
      allowedTCPPorts = [ 30303 30304 42069 ];
      allowedUDPPorts = [ 30303 30304 42069 ];
    };
  };
}
