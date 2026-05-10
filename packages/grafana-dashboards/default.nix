{ fetchurl
, jq
, runCommand
}:
let
  fetchGrafanaDashboard = { id, revision, sha256, name }:
    fetchurl {
      url = "https://grafana.com/api/dashboards/${toString id}/revisions/${toString revision}/download";
      inherit sha256 name;
    };
  # processDashboard substitutes environment variables found in dashboards with constants such as "prometheus" defined in our configurations
  processDashboard = { src, name }:
    runCommand "${name}-processed.json" { buildInputs = [ jq ]; } ''
      jq '
        walk(
          if type == "object" and .datasource? then
            if .datasource == {"type": "prometheus", "uid": "''${DS_PROMETHEUS}"} then
              .datasource = {"type": "prometheus", "uid": "prometheus"}
            elif .datasource == "''${DS_PROMETHEUS}" then
              .datasource = {"type": "prometheus", "uid": "prometheus"}
            elif type == "object" and .datasource.uid? == "''${DS_PROMETHEUS}" then
              .datasource.uid = "prometheus"
            else
              .
            end
          else
            .
          end
        )
        | .id = null
        | .templating.list |= map(
            if .name == "instance_label" then
              .type = "constant" |
              .query = "instance" |
              .current = {"text": "instance", "value": "instance"}
            else
              .
            end
          )
      ' ${src} > $out
    '';
in
{
  node-exporter = processDashboard {
    name = "node-exporter-full";
    src = fetchGrafanaDashboard {
      sha256 = "sha256-pNgn6xgZBEu6LW0lc0cXX2gRkQ8lg/rer34SPE3yEl4=";
      name = "node-exporter-full.json";
      revision = 42;
      id = 1860;
    };
  };
  besu = processDashboard {
    name = "besu-full";
    src = fetchGrafanaDashboard {
      id = 16455;
      revision = 11;
      sha256 = "sha256-jcxo+XUVimulowzHLRN2LrtUhW9Go9DOAXfLefGeHCQ=";
      name = "besu-full.json";
    };
  };
  ebpf-biolatency = processDashboard {
    name = "ebpf-biolatency";
    src = ./ebpf-biolatency.json;
  };
  smartctl = processDashboard {
    name = "smartctl";
    src = fetchGrafanaDashboard {
      id = 22604;
      revision = 2;
      sha256 = "sha256-ci8WE23fZ+ltEKFoUdNNVXsUIV0jqtas79ia2lYIo88=";
      name = "smartctl.json";
    };
  };
  reth = processDashboard {
    name = "reth";
    src = fetchGrafanaDashboard {
      id = 22941;
      revision = 4;
      sha256 = "sha256-cxuUE7m6xlv3buqdUFEwPRH+7hYDde4NxsPtFQzt4rM=";
      name = "reth.json";
    };
  };
  etcd = processDashboard {
    name = "etcd";
    src = fetchGrafanaDashboard {
      id = 21473;
      revision = 3;
      sha256 = "sha256-kVZI1bd9UG9pe58e3/J42uzxuCjfVVylFvkq8GoWFVM=";
      name = "etcd.json";
    };
  };
  tbtc = processDashboard {
    name = "tbtc";
    src = ./tbtc-dashboard.json;
  };
  cgroup = processDashboard {
    name = "cgroup";
    src = ./cgroup-services-dashboard.json;
  };
  coredns = processDashboard {
    name = "coredns";
    src = fetchGrafanaDashboard {
      id = 15762;
      revision = 22;
      sha256 = "sha256-pYYIAoDAkRlU7QOUuDSRlmQjaAV/99AQ29jM1djh0b8=";
      name = "coredns.json";
    };
  };
}
