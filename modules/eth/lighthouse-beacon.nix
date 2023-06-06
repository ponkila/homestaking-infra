{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.lighthouse;
  # split endpoint to address and port
  endpointRegex = "(https?://)?([^:/]+):([0-9]+)(/.*)?$";
  endpointMatch = builtins.match endpointRegex cfg.endpoint;
  endpoint = {
    addr = builtins.elemAt endpointMatch 1;
    port = builtins.elemAt endpointMatch 2;
  };
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
  };

  config = mkIf cfg.enable {
    # package
    environment.systemPackages = with pkgs; [
      lighthouse
    ];

    # service
    systemd.user.services.lighthouse = {
      enable = true;

      description = "beacon, mainnet";
      requires = [ "wg0.service" ];
      after = [ "wg0.service" "mev-boost.service" ];

      serviceConfig = {
        Restart = "always";
        RestartSec = "5s";
        Type = "simple";
      };

      script = ''${pkgs.lighthouse}/bin/lighthouse bn \
        --datadir ${cfg.datadir} \
        --network mainnet \
        --http --http-address ${endpoint.addr} \
        --http-port ${endpoint.port} \
        --http-allow-origin "*" \
        --execution-endpoint ${cfg.exec.endpoint} \
        --execution-jwt %r/jwt.hex \
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
        5052 # TODO: use 'endpoint.port' here by converting it to u16
      ];
    };
  };
}
