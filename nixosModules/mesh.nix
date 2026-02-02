{ config
, inputs
, lib
, outputs
, pkgs
, ...
}: with lib;
let
  cfg = config.mesh;

  inherit (inputs.clib.lib.network.ipv6) fromString;
  meshSelf = map (x: x.address) (map fromString config.systemd.network.networks."50-simple".address);

  nixosConfigurations = lib.map (name: outputs.nixosConfigurations.${name}.config) (builtins.attrNames outputs.nixosConfigurations);

  # a hack to generate ACL from flake outputs by leveraging Nix-JSON bidirectionality
  # assumes you stay in spec: https://git.sr.ht/~msalerno/wirenix/tree/release/item/parsers/v1.nix
  aclConfig = builtins.fromJSON (builtins.readFile outputs.packages.x86_64-linux.acl);
in
{
  options.mesh = {
    enable = mkEnableOption "Enable automatic mesh configuration";
    address = mkOption {
      type = lib.types.str;
      default = concatMapStringsSep "" (x: "[${x}]") meshSelf;
      readOnly = true;
      description = "A read-only value that cannot be overridden";
    };
    addressUnliteral = mkOption {
      type = lib.types.str;
      default = concatMapStringsSep "" (x: x) meshSelf;
      readOnly = true;
      description = "mesh.address but without the square brackets";
    };
    endpoint = mkOption {
      type = types.submodule {
        options = {
          ip = mkOption {
            type = types.str;
            example = "127.0.0.1";
            description = "Endpoint IP or FQDN";
          };

          port = mkOption {
            type = types.port;
            example = 51820;
            description = "Wireguard port";
          };
        };
      };
      description = "Wireguard endpoint";
    };
    # upstream etcd as a submodule
    inherit ((import "${inputs.nixpkgs.outPath}/nixos/modules/services/databases/etcd.nix" {
      inherit pkgs config lib options;
    }).options.services) etcd;
  };

  config = mkIf cfg.enable {

    wirenix = {
      inherit aclConfig;
      enable = true;
      configurer = "networkd";
      keyProviders = [ "agenix-rekey" ];
      peerName = config.networking.hostName;
      secretsDir = ./wirenix/agenix;
    };
    systemd.network.enable = true;

    networking.firewall = {
      allowedUDPPorts = [
        config.mesh.endpoint.port
      ];
      interfaces."simple".allowedTCPPorts = [
        9094 # AlertManager cluster port
        config.services.prometheus.alertmanager.port
      ];
    };

    services = {
      coredns = {
        enable = true;
        # Note: etcd is not a hard requirement if it's already on > 3 hosts
        config = ''
          ${lib.optionalString config.services.etcd.enable ''
          ponkila.nix:1053 {
            etcd {
              path /skydns
              endpoint ${lib.concatStringsSep " " config.services.etcd.listenClientUrls}
            }
            prometheus
            loadbalance
          }
          ''}

          .:1053 {
            forward . 1.1.1.2 2606:4700:4700::1112
            cache
          }
        '';
      };
      # merge autoconfigured fields with whatever the user might provide
      # force the former so the cluster doesn't go wonky
      etcd =
        let
          members = lib.filter (config: config.services.etcd.enable) nixosConfigurations;

          initialCluster = map (node: "${node.wirenix.peerName}=${toString (map (wg: "http://[${wg.address}]") (map fromString node.systemd.network.networks."50-simple".address))}:2380") members;
        in
        mkMerge [
          (mkForce {
            inherit initialCluster;
            name = config.wirenix.peerName;
            listenPeerUrls = map (x: "http://[${x}]:2380") meshSelf;
            listenClientUrls = map (x: "http://[${x}]:2379") meshSelf;
            initialClusterToken = "etcd-cluster-1";
            initialClusterState = "new";
          })
          config.mesh.etcd
        ];

      prometheus =
        let
          alertmanagers = lib.filter (config: config.services.prometheus.alertmanager.enable) nixosConfigurations;
          static_configs = [{
            targets = lib.map (config: "${config.mesh.address}:${toString config.services.prometheus.alertmanager.port}") alertmanagers;
          }];
          id = config.mesh.address;
          clusterPeers = lib.filter (address: address != id) (lib.map (config: config.mesh.address) alertmanagers);
        in
        mkIf config.services.prometheus.enable {
          globalConfig = {
            external_labels = {
              monitor = "global";
            };
          };
          alertmanagers = [{
            inherit static_configs;
            scheme = "http";
          }];
          alertmanager = mkIf config.services.prometheus.alertmanager.enable {
            inherit clusterPeers;
            configuration.route = {
              group_wait = "10s";
              group_interval = "1m";
              repeat_interval = "1h";
            };
            extraFlags = [
              "--cluster.advertise-address=${config.mesh.address}:9094"
              "--cluster.listen-address=${config.mesh.address}:9094"
            ];
          };
          scrapeConfigs = [
            {
              inherit static_configs;
              job_name = "alertmanager";
            }
            (mkIf config.services.etcd.enable {
              job_name = "etcd";
              static_configs =
                let
                  members = lib.filter (config: config.services.etcd.enable) nixosConfigurations;

                  initialCluster = map (node: "${toString (map (wg: "[${wg.address}]") (map fromString node.systemd.network.networks."50-simple".address))}:2379") members;
                in
                [{
                  targets = initialCluster;
                }];
            })
          ];
          ruleFiles = [
            (pkgs.writeText
              "general-rule"
              (builtins.toJSON {
                groups = [
                  {
                    name = "instance_down";
                    rules = [{
                      alert = "InstanceDown";
                      expr = "up < 1";
                      for = "1m";
                      labels = { severity = "alarm"; };
                      annotations = {
                        summary = "Instance {{ $labels.instance }} is down";
                      };
                    }];
                  }
                ];
              })).outPath
          ];
        };
    };
  };
}
