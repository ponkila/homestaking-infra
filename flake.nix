# https://xyno.space/post/nix-darwin-introduction
# https://github.com/Misterio77/nix-starter-configs/tree/main/standard
# https://sourcegraph.com/github.com/shaunsingh/nix-darwin-dotfiles@8ce14d457f912f59645e167707c4d950ae1c3a6e/-/blob/flake.nix
{
  description = "Ethereum home-staking infrastructure powered by Nix";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "http://buidl0.ponkila.com:5000"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "buidl0.ponkila.com:qJZUo9Aji8cTc0v6hIGqbWT8sy+IT/rmSKUFTfhVGGw="
    ];
  };

  inputs = {
    devenv.url = "github:cachix/devenv";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-23.05";
    nixobolus.url = "github:ponkila/nixobolus";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.05";
    nix-serve-ng.url = "github:aristanetworks/nix-serve-ng";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  # Add the inputs declared above to the argument attribute set
  outputs =
    { self
    , flake-parts
    , home-manager
    , nixobolus
    , nixpkgs
    , nixpkgs-stable
    , nix-serve-ng
    , sops-nix
    , ...
    }@inputs:

    flake-parts.lib.mkFlake { inherit inputs; } rec {

      imports = [
        inputs.devenv.flakeModule
      ];

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      perSystem = { pkgs, lib, config, system, ... }: {
        # Nix code formatter, accessible through 'nix fmt'
        formatter = nixpkgs.legacyPackages.${system}.alejandra;

        # Development shell
        # Accessible trough 'nix develop .# --impure' or 'direnv allow'
        devenv.shells = {
          default = {
            packages = with pkgs; [
            git
            nix
            nix-tree
            jq
            sops
            ssh-to-age
            rsync
            zstd
            cpio
          ];
            scripts = {
              nsq.exec = ''
                sh ./scripts/get-store-queries.sh
              '';
              qemu.exec = ''
                nix run path:scripts/init-qemu#init-qemu -- "$@"
              '';
              disko.exec = ''
                nix run github:nix-community/disko -- --mode zap_create_mount ./nixosConfigurations/"$(hostname)"/mounts.nix
              '';
            };
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
                disko       : Format disks according to the mount.nix of the current host

              INFO
          '';
            pre-commit.hooks = {
              alejandra.enable = true;
              shellcheck.enable = true;
            };
            # Workaround for https://github.com/cachix/devenv/issues/760
            containers = pkgs.lib.mkForce {};
          };
        };

        # Custom packages and aliases for building hosts
        # Accessible through 'nix build', 'nix run', etc
        packages = with flake.nixosConfigurations; {
          "dinar-ephemeral-alpha" = dinar-ephemeral-alpha.config.system.build.isoImage;
          "hetzner-ephemeral-alpha" = hetzner-ephemeral-alpha.config.system.build.kexecTree;
          "hetzner-ephemeral-beta" = hetzner-ephemeral-beta.config.system.build.kexecTree;
          "dinar-ephemeral-beta" = dinar-ephemeral-beta.config.system.build.isoImage;
          "ponkila-ephemeral-beta" = ponkila-ephemeral-beta.config.system.build.kexecTree;
          "ponkila-ephemeral-gamma" = ponkila-ephemeral-gamma.config.system.build.kexecTree;
        };
      };
      flake =
        let
          inherit (self) outputs;

          ponkila-ephemeral-beta = {
            system = "x86_64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./nixosConfigurations/ponkila-ephemeral-beta
              nixobolus.nixosModules.kexecTree
              nixobolus.nixosModules.homestakeros
              sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  outputs.overlays.additions
                  outputs.overlays.modifications
                ];
              }
              {
                # Bootloader for x86_64-linux / aarch64-linux
                boot.loader.systemd-boot.enable = true;
                boot.loader.efi.canTouchEfiVariables = true;
              }
            ];
          };

          ponkila-ephemeral-gamma = {
            system = "aarch64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./nixosConfigurations/ponkila-ephemeral-gamma
              nixobolus.nixosModules.kexecTree
              nixobolus.nixosModules.homestakeros
              sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  outputs.overlays.additions
                  outputs.overlays.modifications
                  # Workaround for https://github.com/NixOS/nixpkgs/issues/154163
                  # This issue only happens with the isoImage format
                  (final: super: {
                    makeModulesClosure = x:
                      super.makeModulesClosure (x // { allowMissing = true; });
                  })
                ];
              }
              {
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
              ./modules/sys2x/gc.nix
              ./home-manager/juuso.nix
              ./home-manager/kari.nix
              ./home-manager/allu.nix
              ./home-manager/tommi.nix
              nixobolus.nixosModules.kexecTree
              nix-serve-ng.nixosModules.default
              home-manager.nixosModules.home-manager
              {
                nixpkgs.overlays = [
                  outputs.overlays.additions
                  outputs.overlays.modifications
                ];
              }
              {
                # Bootloader for x86_64-linux / aarch64-linux
                boot.loader.systemd-boot.enable = true;
                boot.loader.efi.canTouchEfiVariables = true;
              }
            ];
          };

          hetzner-ephemeral-beta = {
            system = "aarch64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./nixosConfigurations/hetzner-ephemeral-beta
              ./modules/sys2x/gc.nix
              ./home-manager/juuso.nix
              ./home-manager/kari.nix
              ./home-manager/allu.nix
              ./home-manager/tommi.nix
              nixobolus.nixosModules.kexecTree
              nix-serve-ng.nixosModules.default
              home-manager.nixosModules.home-manager
              {
                nixpkgs.overlays = [
                  outputs.overlays.additions
                  outputs.overlays.modifications
                ];
              }
              {
                # Bootloader for x86_64-linux / aarch64-linux
                boot.loader.systemd-boot.enable = true;
                boot.loader.efi.canTouchEfiVariables = true;
              }
            ];
          };

          dinar-ephemeral-alpha = {
            system = "x86_64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./nixosConfigurations/dinar-ephemeral-alpha
              nixobolus.nixosModules.isoImage
              nixobolus.nixosModules.homestakeros
              sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  outputs.overlays.additions
                  outputs.overlays.modifications
                ];
              }
            ];
          };

          dinar-ephemeral-beta = {
            system = "x86_64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./nixosConfigurations/dinar-ephemeral-beta
              nixobolus.nixosModules.isoImage
              nixobolus.nixosModules.homestakeros
              sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  outputs.overlays.additions
                  outputs.overlays.modifications
                ];
              }
            ];
          };

        in
        {
          # Patches and version overrides for some packages
          overlays = import ./overlays { inherit inputs; };

          # NixOS configuration entrypoints
          nixosConfigurations = with nixpkgs.lib; {
            "dinar-ephemeral-alpha" = nixosSystem dinar-ephemeral-alpha;
            "dinar-ephemeral-beta" = nixosSystem dinar-ephemeral-beta;
            "ponkila-ephemeral-beta" = nixosSystem ponkila-ephemeral-beta;
          } // (with nixpkgs-stable.lib; {
            "hetzner-ephemeral-alpha" = nixosSystem hetzner-ephemeral-alpha;
            "hetzner-ephemeral-beta" = nixosSystem hetzner-ephemeral-beta;
            "ponkila-ephemeral-gamma" = nixosSystem ponkila-ephemeral-gamma;
          });
        };
    };
}
