# https://xyno.space/post/nix-darwin-introduction
# https://github.com/Misterio77/nix-starter-configs/tree/main/standard
# https://sourcegraph.com/github.com/shaunsingh/nix-darwin-dotfiles@8ce14d457f912f59645e167707c4d950ae1c3a6e/-/blob/flake.nix
{
  description = "Ethereum home-staking infrastructure powered by Nix";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.url = "github:oddlama/agenix-rekey";
    agenix.url = "github:ryantm/agenix";
    devenv.url = "github:cachix/devenv";
    flake-parts.url = "github:hercules-ci/flake-parts";
    homestakeros-base.inputs.nixpkgs.follows = "nixpkgs";
    homestakeros-base.url = "github:ponkila/HomestakerOS?dir=nixosModules/base";
    homestakeros.url = "github:ponkila/HomestakerOS";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    sops-nix.url = "github:Mic92/sops-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    wirenix.url = "sourcehut:~msalerno/wirenix?rev=c1e3bf1800de10da8f3af320415a31e3cb28b555";
    clib.url = "github:nix-community/nixpkgs.lib";
  };

  # Add the inputs declared above to the argument attribute set
  outputs = { self, ... }@inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } rec {
      systems = inputs.nixpkgs.lib.systems.flakeExposed;
      imports = [
        inputs.agenix-rekey.flakeModule
        inputs.devenv.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        { self'
        , pkgs
        , lib
        , config
        , system
        , ...
        }: {
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

          # Development shell
          # Accessible trough 'nix develop .# --impure' or 'direnv allow'
          devenv.shells = {
            default = {
              packages = with pkgs; [
                config.agenix-rekey.package
                jq
                self'.packages.init-qemu
                self'.packages.nsq
                sops
                ssh-to-age
              ];
              env = {
                NIX_CONFIG = ''
                  accept-flake-config = true
                  extra-experimental-features = flakes nix-command
                  warn-dirty = false
                '';
              };
              enterShell = ''
                cat <<INFO

                ### homestaking-infra ###

                Available commands:

                  nsq         : Get and update the nix-store queries
                  init-qemu   : Use QEMU to boot up a host
                  lens        : Update web UI assets

                INFO
              '';
              pre-commit.hooks = {
                nixpkgs-fmt.enable = true;
                shellcheck.enable = true;
              };
              # Workaround for https://github.com/cachix/devenv/issues/760
              containers = pkgs.lib.mkForce { };
              scripts.lens.exec = ''
                nix eval --no-warn-dirty --json github:ponkila/homestakeros#schema | jq > nixosModules/homestakeros/options.json \
                && nix run --no-warn-dirty github:ponkila/homestakeros#update-json
              '';
            };
          };

          # Custom packages, accessible trough 'nix build', 'nix run', etc.
          packages =
            rec {
              "nsq" = pkgs.callPackage ./packages/nsq { };
              "init-qemu" = pkgs.callPackage ./packages/init-qemu { };
            }
            # Entrypoint aliases, accessible trough 'nix build'
            // (with flake.nixosConfigurations; {
              "dinar-ephemeral-beta" = dinar-ephemeral-beta.config.system.build.kexecTree;
              "hetzner-ephemeral-alpha" = hetzner-ephemeral-alpha.config.system.build.kexecTree;
              "kaakkuri-ephemeral-alpha" = kaakkuri-ephemeral-alpha.config.system.build.kexecTree;
              "ponkila-ephemeral-beta" = ponkila-ephemeral-beta.config.system.build.kexecTree;
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
            identity = ./nixosModules/agenix-rekey/masterIdentities/juuso.hmac;
            pubkey = "age12lz3jyd2weej5c4mgmwlwsl0zmk2tdgvtflctgryx6gjcaf3yfsqgt7rnz";
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
              inputs.sops-nix.nixosModules.sops
              inputs.wirenix.nixosModules.default
              {
                nixpkgs.overlays = [
                  inputs.homestakeros.overlays.default
                ];
                boot.loader.grub.enable = false;
                age.rekey = {
                  localStorageDir = ./nixosConfigurations/ponkila-ephemeral-beta/secrets/agenix-rekey;
                  masterIdentities = [{
                    identity = ./nixosModules/agenix-rekey/masterIdentities/juuso.hmac;
                    pubkey = "age12lz3jyd2weej5c4mgmwlwsl0zmk2tdgvtflctgryx6gjcaf3yfsqgt7rnz";
                  }];
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
                  masterIdentities = [ jesse juuso ];
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
                  masterIdentities = [{
                    identity = ./nixosModules/agenix-rekey/masterIdentities/juuso.hmac;
                    pubkey = "age12lz3jyd2weej5c4mgmwlwsl0zmk2tdgvtflctgryx6gjcaf3yfsqgt7rnz";
                  }];
                  storageMode = "local";
                };
              }
            ];
          };

          dinar-ephemeral-beta = {
            system = "x86_64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./nixosConfigurations/dinar-ephemeral-beta
              inputs.homestakeros-base.nixosModules.base
              inputs.homestakeros-base.nixosModules.kexecTree
              inputs.homestakeros.nixosModules.homestakeros

              inputs.agenix-rekey.nixosModules.default
              inputs.agenix.nixosModules.default
              inputs.sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  inputs.homestakeros.overlays.default
                ];
                boot.loader.grub.enable = false;
                age.rekey = {
                  localStorageDir = ./. + "/nixosConfigurations/dinar-ephemeral-beta/secrets/agenix-rekey";
                  masterIdentities = [{
                    identity = ./nixosModules/agenix-rekey/masterIdentities/juuso.hmac;
                    pubkey = "age12lz3jyd2weej5c4mgmwlwsl0zmk2tdgvtflctgryx6gjcaf3yfsqgt7rnz";
                  }];
                  storageMode = "local";
                };
              }
            ];
          };
        in
        {
          # NixOS configuration entrypoints
          nixosConfigurations = with inputs.nixpkgs.lib; {
            "dinar-ephemeral-beta" = nixosSystem dinar-ephemeral-beta;
            "hetzner-ephemeral-alpha" = nixosSystem hetzner-ephemeral-alpha;
            "kaakkuri-ephemeral-alpha" = nixosSystem kaakkuri-ephemeral-alpha;
            "ponkila-ephemeral-beta" = nixosSystem ponkila-ephemeral-beta;
          };
        };
    };
}
