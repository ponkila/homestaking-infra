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
    devenv.url = "github:cachix/devenv";
    flake-parts.url = "github:hercules-ci/flake-parts";
    homestakeros-base.inputs.nixpkgs.follows = "nixpkgs";
    homestakeros-base.url = "github:ponkila/HomestakerOS?dir=nixosModules/base";
    homestakeros.url = "github:ponkila/HomestakerOS";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  # Add the inputs declared above to the argument attribute set
  outputs = { self, ... }@inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } rec {
      systems = inputs.nixpkgs.lib.systems.flakeExposed;
      imports = [
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
                jq
                sops
                ssh-to-age
                self'.packages.init-qemu
                self'.packages.nsq
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
              "dinar-ephemeral-alpha" = dinar-ephemeral-alpha.config.system.build.kexecTree;
              "dinar-ephemeral-beta" = dinar-ephemeral-beta.config.system.build.kexecTree;
              "hetzner-ephemeral-alpha" = hetzner-ephemeral-alpha.config.system.build.kexecTree;
              "ponkila-ephemeral-beta" = ponkila-ephemeral-beta.config.system.build.kexecTree;
              "ponkila-ephemeral-gamma" = ponkila-ephemeral-gamma.config.system.build.kexecTree;
            });
        };
      flake =
        let
          inherit (self) outputs;

          ponkila-ephemeral-beta = {
            system = "x86_64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./nixosConfigurations/ponkila-ephemeral-beta
              inputs.homestakeros-base.nixosModules.base
              inputs.homestakeros-base.nixosModules.kexecTree
              inputs.homestakeros.nixosModules.homestakeros

              inputs.sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  inputs.homestakeros.overlays.default
                ];
                boot.loader.grub.enable = false;
              }
            ];
          };

          ponkila-ephemeral-gamma = {
            system = "aarch64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./nixosConfigurations/ponkila-ephemeral-gamma
              inputs.homestakeros-base.nixosModules.base
              inputs.homestakeros-base.nixosModules.kexecTree
              inputs.homestakeros.nixosModules.homestakeros
              inputs.sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  inputs.homestakeros.overlays.default
                  # Workaround for https://github.com/NixOS/nixpkgs/issues/154163
                  # This issue only happens with the isoImage format
                  (_final: super: {
                    makeModulesClosure = x:
                      super.makeModulesClosure (x // { allowMissing = true; });
                  })
                ];
                # Bootloader for RaspberryPi 4
                boot.loader.raspberryPi = {
                  enable = true;
                  version = 4;
                };
                boot.loader.grub.enable = false;
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
              inputs.sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  inputs.homestakeros.overlays.default
                ];
                boot.loader.grub.enable = false;
              }
            ];
          };

          dinar-ephemeral-alpha = {
            system = "x86_64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./nixosConfigurations/dinar-ephemeral-alpha
              inputs.homestakeros-base.nixosModules.base
              inputs.homestakeros-base.nixosModules.kexecTree
              inputs.homestakeros.nixosModules.homestakeros
              inputs.sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  inputs.homestakeros.overlays.default
                ];
                boot.loader.grub.enable = false;
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
              inputs.sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  inputs.homestakeros.overlays.default
                ];
                boot.loader.grub.enable = false;
              }
            ];
          };
        in
        {
          # NixOS configuration entrypoints
          nixosConfigurations = with inputs.nixpkgs.lib;
            {
              "dinar-ephemeral-alpha" = nixosSystem dinar-ephemeral-alpha;
              "dinar-ephemeral-beta" = nixosSystem dinar-ephemeral-beta;
              "hetzner-ephemeral-alpha" = nixosSystem hetzner-ephemeral-alpha;
              "ponkila-ephemeral-beta" = nixosSystem ponkila-ephemeral-beta;
            }
            // (with inputs.nixpkgs-stable.lib; {
              "ponkila-ephemeral-gamma" = nixosSystem ponkila-ephemeral-gamma;
            });
        };
    };
}
