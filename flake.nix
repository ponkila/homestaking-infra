# https://xyno.space/post/nix-darwin-introduction
# https://github.com/Misterio77/nix-starter-configs/tree/main/standard
# https://sourcegraph.com/github.com/shaunsingh/nix-darwin-dotfiles@8ce14d457f912f59645e167707c4d950ae1c3a6e/-/blob/flake.nix
{
  description = "Ethereum home-staking infrastructure powered by Nix";

  inputs = {
    actions-nix.url = "github:nialov/actions.nix";
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.url = "github:oddlama/agenix-rekey";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.url = "github:ryantm/agenix";
    clib.url = "github:nix-community/nixpkgs.lib";
    flake-parts.url = "github:hercules-ci/flake-parts";
    homestakeros-base.inputs.nixpkgs.follows = "nixpkgs";
    homestakeros-base.url = "github:ponkila/HomestakerOS?dir=nixosModules/base";
    homestakeros.inputs.nixpkgs.follows = "nixpkgs";
    homestakeros.url = "github:ponkila/HomestakerOS";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    wirenix.inputs.nixpkgs.follows = "nixpkgs";
    wirenix.url = "sourcehut:~msalerno/wirenix";
    cgroup-exporter.inputs.nixpkgs.follows = "nixpkgs";
    cgroup-exporter.url = "github:arianvp/cgroup-exporter";
    git-hooks.follows = "actions-nix/git-hooks";
  };

  # Add the inputs declared above to the argument attribute set
  outputs = { self, ... }@inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } rec {

    systems = inputs.nixpkgs.lib.systems.flakeExposed;
    imports = [
      inputs.actions-nix.flakeModules.default
      inputs.agenix-rekey.flakeModule
      inputs.git-hooks.flakeModule
      inputs.treefmt-nix.flakeModule
    ];

    perSystem = { pkgs, config, system, lib, ... }: {

      # Overlays
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.homestakeros.overlays.default
        ];
        config = { };
      };

      # Nix code formatter, accessible through 'nix fmt'
      treefmt.config = {
        projectRootFile = "flake.nix";
        flakeFormatter = true;
        flakeCheck = true;
        programs = {
          deadnix.enable = true;
          nixpkgs-fmt.enable = true;
          statix.enable = true;
        };
        settings.global.excludes = [ "devShells/keep-core/flake.nix" ];
      };

      # Pre-commit hooks
      pre-commit.check.enable = false;
      pre-commit.settings.hooks.treefmt = {
        enable = true;
        package = config.treefmt.build.wrapper;
      };

      # Development shell
      devShells.default =
        let
          lens = pkgs.writeShellScriptBin "lens" ''
            nix eval --no-warn-dirty --json github:ponkila/homestakeros#schema | jq > nixosModules/homestakeros/options.json \
            && nix run --no-warn-dirty github:ponkila/homestakeros#update-json
          '';
          nsq = pkgs.writeShellScriptBin "nsq" ''
            exec ${config.packages.nsq}/bin/nsq "$@"
          '';
        in
        pkgs.mkShell {
          packages = [
            config.agenix-rekey.package
            config.pre-commit.settings.package
            lens
            nsq
            pkgs.jq
            pkgs.sops
            pkgs.ssh-to-age
          ];
          shellHook = ''
            ${config.pre-commit.installationScript}
            echo ""
            echo " homestaking-infra devshell"
            echo ""
            echo " commands:"
            echo "   lens  - Update web UI assets"
            echo "   nsq   - Get and update the nix-store queries"
            echo ""
          '';
        };

      # Custom packages, accessible trough 'nix build', 'nix run', etc.
      packages =
        let
          dashboards = pkgs.callPackages ./packages/grafana-dashboards { };
          alerts = pkgs.callPackages ./packages/prometheus-alerts { };
        in
        {
          "nsq" = pkgs.callPackage ./packages/nsq { };
          "reth" = pkgs.reth.overrideAttrs (_: {
            cargoBuildType = "maxperf";
          });
          "acl" = pkgs.writeText "acl.nix"
            (builtins.toJSON (import ./nixosModules/wirenix/acl.nix {
              inherit (flake) nixosConfigurations;
              inherit lib;
              subnetName = "simple";
            }));
          # useful to check that each dashboard evaluates
          "grafana-dashboards-all" = pkgs.linkFarm "grafana-dashboards" (
            lib.mapAttrsToList
              (dashboardName: drv: {
                name = dashboardName;
                path = drv;
              })
              dashboards
          );
          "awesome-prometheus-alerts" = pkgs.callPackage ./packages/awesome-prometheus-alerts { };
          "prometheus-alerts-all" = pkgs.linkFarm "prometheus-alerts" (
            lib.mapAttrsToList
              (alertName: drv: {
                name = alertName;
                path = drv;
              })
              alerts
          );
        }
        # generator for each individual dashboard
        // (lib.mapAttrs' (name: drv: lib.nameValuePair "grafana-dashboard-${name}" drv) dashboards)
        // (lib.mapAttrs' (name: drv: lib.nameValuePair "prometheus-alert-${name}" drv) alerts)
        # Entrypoint aliases, accessible trough 'nix build'
        // (with flake.nixosConfigurations; {
          "hetzner-ephemeral-alpha" = hetzner-ephemeral-alpha.config.system.build.kexecTree;
          "kaakkuri-ephemeral-alpha" = kaakkuri-ephemeral-alpha.config.system.build.kexecTree;
          "ponkila-ephemeral-beta" = ponkila-ephemeral-beta.config.system.build.kexecTree;
          "ponkila-ephemeral-sigma" = ponkila-ephemeral-sigma.config.system.build.kexecTree;
        });
    };
    flake =
      let
        inherit (self) outputs;
        jesse = {
          identity = ./nixosModules/agenix-rekey/masterIdentities/jesse.hmac;
          pubkey = "age1fm70hduvuy5mu5n9jhv7l4u6d9pqclj2ef9jq6w2ptpatjsm25ysdx3py9";
        };
        juuso = {
          muro = {
            identity = ./nixosModules/agenix-rekey/masterIdentities/juuso-muro.hmac;
            pubkey = "age1des79v6xqh3ylway0lwlggf0ldckcej0w3a4njytvq6us2yp3erszz39uk";
          };
          starlabs = {
            identity = ./nixosModules/agenix-rekey/masterIdentities/juuso-starlabs.hmac;
            pubkey = "age12lz3jyd2weej5c4mgmwlwsl0zmk2tdgvtflctgryx6gjcaf3yfsqgt7rnz";
          };
        };

        ponkila-ephemeral-beta = {
          system = "x86_64-linux";
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixosConfigurations/ponkila-ephemeral-beta
            inputs.homestakeros-base.nixosModules.base
            inputs.homestakeros-base.nixosModules.kexecTree
            inputs.homestakeros.nixosModules.homestakeros

            inputs.agenix-rekey.nixosModules.default
            inputs.agenix.nixosModules.default
            inputs.cgroup-exporter.nixosModules.default
            inputs.sops-nix.nixosModules.sops
            inputs.wirenix.nixosModules.default
            {
              nixpkgs.overlays = [
                inputs.homestakeros.overlays.default
              ];
              boot.loader.grub.enable = false;
              age.rekey = {
                localStorageDir = ./nixosConfigurations/ponkila-ephemeral-beta/secrets/agenix-rekey;
                masterIdentities = [ jesse juuso.starlabs juuso.muro ];
                storageMode = "local";
              };
            }
          ];
        };

        kaakkuri-ephemeral-alpha = {
          system = "x86_64-linux";
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixosConfigurations/kaakkuri-ephemeral-alpha
            inputs.homestakeros-base.nixosModules.base
            inputs.homestakeros-base.nixosModules.kexecTree
            inputs.homestakeros.nixosModules.homestakeros

            inputs.cgroup-exporter.nixosModules.default
            inputs.agenix-rekey.nixosModules.default
            inputs.agenix.nixosModules.default
            inputs.sops-nix.nixosModules.sops
            inputs.wirenix.nixosModules.default
            {
              nixpkgs.overlays = [
                inputs.homestakeros.overlays.default
              ];
              boot.loader.grub.enable = false;
              age.rekey = {
                localStorageDir = ./nixosConfigurations/kaakkuri-ephemeral-alpha/secrets/agenix-rekey;
                masterIdentities = [ jesse juuso.starlabs juuso.muro ];
                storageMode = "local";
              };
            }
          ];
        };

        hetzner-ephemeral-alpha = {
          system = "x86_64-linux";
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixosConfigurations/hetzner-ephemeral-alpha
            inputs.homestakeros-base.nixosModules.base
            inputs.homestakeros-base.nixosModules.kexecTree
            inputs.homestakeros.nixosModules.homestakeros


            inputs.cgroup-exporter.nixosModules.default
            inputs.agenix-rekey.nixosModules.default
            inputs.agenix.nixosModules.default
            inputs.sops-nix.nixosModules.sops
            inputs.wirenix.nixosModules.default
            {
              nixpkgs.overlays = [
                inputs.homestakeros.overlays.default
              ];
              boot.loader.grub.enable = false;
              age.rekey = {
                localStorageDir = ./nixosConfigurations/hetzner-ephemeral-alpha/secrets/agenix-rekey;
                masterIdentities = [ jesse juuso.starlabs juuso.muro ];
                storageMode = "local";
              };
            }
          ];
        };

        ponkila-ephemeral-sigma = {
          system = "x86_64-linux";
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixosConfigurations/ponkila-ephemeral-sigma
            inputs.homestakeros-base.nixosModules.base
            inputs.homestakeros-base.nixosModules.kexecTree
            inputs.homestakeros.nixosModules.homestakeros

            inputs.cgroup-exporter.nixosModules.default
            inputs.agenix-rekey.nixosModules.default
            inputs.agenix.nixosModules.default
            inputs.wirenix.nixosModules.default
            {
              nixpkgs.overlays = [
                inputs.homestakeros.overlays.default
              ];
              boot.loader.grub.enable = false;
              age.rekey = {
                localStorageDir = ./nixosConfigurations/ponkila-ephemeral-sigma/secrets/agenix-rekey;
                masterIdentities = [ jesse juuso.starlabs juuso.muro ];
                storageMode = "local";
              };
            }
          ];
        };

      in
      {
        # nix run .#render-workflows
        actions-nix = {
          defaultValues = {
            jobs = {
              timeout-minutes = 30;
              runs-on = "ubuntu-latest";
            };
          };
          pre-commit.enable = true;
          workflows = {
            ".github/workflows/main.yaml" = {
              on = {
                push.branches = [ "main" ];
                workflow_dispatch = { };
                pull_request = { };
              };
              jobs = {
                nix-flake-check = {
                  steps = with inputs.actions-nix.lib.steps; [
                    actionsCheckout
                    DeterminateSystemsNixInstallerAction
                    runNixFlakeCheck
                  ];
                };
              };
            };
          };
        };

        # NixOS configuration entrypoints
        nixosConfigurations = with inputs.nixpkgs.lib; {
          "hetzner-ephemeral-alpha" = nixosSystem hetzner-ephemeral-alpha;
          "kaakkuri-ephemeral-alpha" = nixosSystem kaakkuri-ephemeral-alpha;
          "ponkila-ephemeral-beta" = nixosSystem ponkila-ephemeral-beta;
          "ponkila-ephemeral-sigma" = nixosSystem ponkila-ephemeral-sigma;
        };

        nixosModules = {
          monitoring = { imports = [ ./nixosModules/monitoring.nix ]; };
        };
      };
  };
}
