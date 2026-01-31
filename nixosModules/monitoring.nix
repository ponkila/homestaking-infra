{ config
, lib
, outputs
, ...
}: with lib;
let
  cfg = config.monitoring;
in
{
  options.monitoring = {
    enable = mkEnableOption "";
    grafana = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "";
          address = mkOption {
            type = types.str;
            description = "What endpoint to bind Grafana";
          };
        };
      };
    };
    logs = mkEnableOption "";
    traces = mkEnableOption "";
    alerts = mkEnableOption "";
  };

  config = mkIf cfg.enable {

    services.prometheus = mkIf cfg.alerts {
      enable = true;
      globalConfig = {
        scrape_interval = "15s";
      };
      extraFlags = [
        "--log.level=warn"
        "--log.format=json"
      ] ++ (lib.optionals cfg.traces [
        "--web.enable-remote-write-receiver"
      ]);
      alertmanager = {
        enable = true;
      };
      ruleFiles = [
        outputs.packages.x86_64-linux.prometheus-alert-systemd.outPath
      ] ++
      (lib.optionals config.services.prometheus.exporters.node.enable [
        "${outputs.packages.x86_64-linux.awesome-prometheus-alerts.outPath}/host-and-hardware/node-exporter.yml"
      ]) ++
      (lib.optionals config.services.prometheus.exporters.smartctl.enable [
        "${outputs.packages.x86_64-linux.awesome-prometheus-alerts.outPath}/s.m.a.r.t-device-monitoring/smartctl-exporter.yml"
      ]) ++
      (lib.optionals config.mesh.etcd.enable [
        "${outputs.packages.x86_64-linux.awesome-prometheus-alerts.outPath}/etcd/embedded-exporter.yml"
      ])
      ;
    };

    services.tempo = mkIf cfg.traces {
      enable = true;
      settings = {
        server = {
          http_listen_port = 3200;
          grpc_listen_port = 9096;
          log_format = "json";
          log_level = "warn";
        };
        querier = {
          frontend_worker = {
            frontend_address = "127.0.0.1:9096";
          };
        };
        metrics_generator = {
          registry = {
            external_labels = {
              source = "tempo";
            };
          };
          storage = {
            path = "/var/lib/tempo/generator/wal";
            remote_write = [
              { url = "http://localhost:${toString config.services.prometheus.port}/api/v1/write"; }
            ];
          };
          traces_storage = {
            path = "/var/lib/tempo/generator/traces";
          };
        };
        overrides = {
          defaults = {
            metrics_generator = {
              processors = [ "service-graphs" "span-metrics" "local-blocks" ];
            };
          };
        };
        distributor = {
          receivers = {
            otlp = {
              protocols = {
                grpc = { endpoint = "127.0.0.1:4317"; };
                http = { endpoint = "127.0.0.1:4318"; };
              };
            };
          };
        };
        ingester = {
          trace_idle_period = "30s";
          max_block_bytes = 1000000;
          max_block_duration = "5m";
        };
        compactor = {
          compaction = {
            compaction_window = "1h";
            max_block_bytes = 100000000;
            block_retention = "48h";
          };
        };
        storage = {
          trace = {
            backend = "local";
            local = {
              path = "/var/lib/tempo/traces";
            };
            wal = {
              path = "/var/lib/tempo/wal";
            };
          };
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ config.services.grafana.settings.server.http_port ];
    services.grafana = mkIf cfg.grafana.enable {
      enable = true;
      settings = {
        server.http_port = 3000;
        server.http_addr = cfg.grafana.address;
        security.admin_password = "changeme"; # TODO: agenix
        log.level = "warn";
        "log.console".format = "json";
      };
      provision = {
        datasources.settings.datasources =
          (optional config.services.prometheus.enable {
            name = "Prometheus";
            type = "prometheus";
            uid = "prometheus";
            url = "http://localhost:9090";
            isDefault = true;
            jsonData = {
              # unmatching query intervals leads to blank graphs
              # see, e.g.: https://github.com/rfmoz/grafana-dashboards/issues/169
              timeInterval = config.services.prometheus.globalConfig.scrape_interval;
            };
          }) ++
          (optional cfg.traces {
            name = "Tempo";
            type = "tempo";
            uid = "tempo";
            url = "http://localhost:${toString config.services.tempo.settings.server.http_listen_port}";
          }) ++
          (optional cfg.logs {
            name = "Loki";
            type = "loki";
            url = "http://localhost:${toString config.services.loki.configuration.server.http_listen_port}";
          });
      };
    };

    services.loki = mkIf cfg.logs {
      enable = true;
      configuration = {
        auth_enabled = false;
        server = {
          http_listen_port = 3100;
          log_format = "json";
          log_level = "warn";
        };
        common = {
          ring = {
            instance_addr = "127.0.0.1";
            kvstore = {
              store = "inmemory";
            };
          };
          replication_factor = 1;
          path_prefix = "/var/lib/loki";
        };
        schema_config = {
          configs = [{
            from = "2020-05-15";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }];
        };
        storage_config = {
          filesystem = {
            directory = "/var/lib/loki/chunks";
          };
        };
        ruler = lib.mkIf config.services.prometheus.alertmanager.enable {
          storage = {
            type = "local";
            local = {
              directory = "/var/lib/loki/rules";
            };
          };
          rule_path = "/var/lib/loki/rules-temp";
          alertmanager_url = "http://localhost:9093";
          enable_api = true;
        };
      };
    };

    services.vector = mkIf cfg.logs {
      enable = true;
      journaldAccess = true;
      settings = {
        api.enabled = true;
        sources.journald = {
          type = "journald";
        };
        transforms.journald-grafana = {
          type = "remap";
          inputs = [ "journald" ];
          source = ''
            .service_name = ._SYSTEMD_UNIT
          '';
        };
        sinks.loki = {
          type = "loki";
          inputs = [ "journald-grafana" ];
          endpoint = "http://localhost:${toString config.services.loki.configuration.server.http_listen_port}";
          encoding.codec = "text";
          labels = {
            service = "{{ _SYSTEMD_UNIT }}";
          };
        };
      };
    };

  };
}
