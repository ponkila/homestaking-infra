{ writeText
}:

let
  mkAlert = { name, groups }:
    writeText name (builtins.toJSON { inherit groups; });
in
{

  ipmi = mkAlert {
    name = "ipmi-alerts";
    groups = [
      {
        name = "sel-recording";
        rules = [
          {
            record = "ipmi_sel_logs_24h";
            expr = "increase(ipmi_sel_logs_count[24h])";
          }
        ];
      }
      {
        name = "ipmi-alerts";
        rules = [
          {
            alert = "IPMISELNewEntry";
            expr = ''
              ipmi_sel_logs_24h > 0
              and on() hour() == 9
              and on() minute() < 5
            '';
            labels = {
              severity = "info";
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
    groups = [
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
    groups = [
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
    groups = [
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
