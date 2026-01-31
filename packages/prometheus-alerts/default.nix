{ writeText
}:

let
  mkAlert = { name, alerts }:
    writeText name (builtins.toJSON { groups = alerts; });
in
{

  ipmi = mkAlert {
    name = "ipmi-alerts";
    alerts = [
      {
        name = "ipmi-alerts";
        rules = [
          {
            alert = "IPMISELNewEntry";
            expr = ''increase(ipmi_sel_logs_count[5m]) > 0'';
            "for" = "0m";
            labels = {
              severity = "warning";
            };
            annotations = {
              summary = "New IPMI SEL entry detected";
              description = "SEL log count increased by {{ $value }}. Free space: {{ with printf \"ipmi_sel_free_space_bytes{instance='%s'}\" .Labels.instance | query }}{{ . | first | value | humanize1024 }}B{{ end }}";
            };
          }
        ];
      }
    ];
  };
  rasdaemon = mkAlert {
    name = "rasdaemon-alerts";
    alerts = [
      {
        name = "rasdaemon";
        rules = [
          {
            alert = "RasdaemonHardwareError";
            expr = ''{__name__=~"rasdaemon_.*_total"} > 0'';
            labels = {
              severity = "warning";
            };
            annotations = {
              summary = "Hardware error detected: {{ $labels.__name__ }}";
              description = "Rasdaemon detected a hardware error. Labels: {{ $labels }}";
            };
          }
        ];
      }
    ];
  };
  lighthouse = mkAlert {
    name = "lighthouse-alerts";
    alerts = [
      {
        name = "lighthouse";
        rules = [
          {
            alert = "BeaconSyncDeviation";
            expr = "abs(beacon_head_state_slot - on() group_left max(beacon_head_state_slot)) > 5";
            "for" = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "Beacon chain instances out of sync by more than 5 blocks";
              description = "Implies execution layer disconnection or significant performance regressions.";
            };
          }
        ];
      }
    ];
  };
  systemd = mkAlert {
    name = "systemd-alerts";
    alerts = [
      {
        name = "systemd";
        rules = [
          {
            alert = "SystemdServiceFailed";
            expr = ''node_systemd_unit_state{state="failed"} == 1'';
            "for" = "0m";
            labels = {
              severity = "critical";
            };
            annotations = {
              summary = "Service {{ $labels.name }} failed";
            };
          }
        ];
      }
    ];
  };

}
