# https://xyno.space/post/nix-darwin-introduction
# https://github.com/Misterio77/nix-starter-configs/tree/main/standard
# https://sourcegraph.com/github.com/shaunsingh/nix-darwin-dotfiles@8ce14d457f912f59645e167707c4d950ae1c3a6e/-/blob/flake.nix
{
  description = "Ethereum home-staking infrastructure powered by Nix";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "http://192.168.100.10:5000"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "192.168.100.10:0qiW05TfoEi8DCkNqeKlbXvnKfMi8bA4fiyTKSYY3P8="
    ];
  };

  inputs = {
    devenv.url = "github:cachix/devenv";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixobolus.url = "github:ponkila/nixobolus";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.05";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  # Add the inputs declared above to the argument attribute set
  outputs = {
    self,
    flake-parts,
    nixobolus,
    nixpkgs,
    nixpkgs-stable,
    sops-nix,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} rec {
      systems = nixpkgs.lib.systems.flakeExposed;
      imports = [
        inputs.devenv.flakeModule
      ];

      perSystem = {
        self',
        pkgs,
        lib,
        config,
        system,
        ...
      }: {
        # Overlays
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            nixobolus.overlays.default
          ];
          config = {};
        };

        # Nix code formatter, accessible through 'nix fmt'
        formatter = nixpkgs.legacyPackages.${system}.alejandra;

        # Development shell
        # Accessible trough 'nix develop .# --impure' or 'direnv allow'
        devenv.shells = {
          default = {
            packages = with pkgs; [
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

        # Custom packages, accessible trough 'nix build', 'nix run', etc.
        packages =
          rec {
            "nsq" = pkgs.callPackage ./packages/nsq {};
            "init-qemu" = pkgs.callPackage ./packages/init-qemu {};
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
      flake = let
        inherit (self) outputs;

        ponkila-ephemeral-beta = {
          system = "x86_64-linux";
          specialArgs = {inherit inputs outputs;};
          modules = [
            ./nixosConfigurations/ponkila-ephemeral-beta
            nixobolus.nixosModules.kexecTree
            nixobolus.nixosModules.homestakeros
            sops-nix.nixosModules.sops
            {
              nixpkgs.overlays = [
                nixobolus.overlays.default
              ];
              boot.loader.grub.enable = false;
            }
          ];
        };

        ponkila-ephemeral-gamma = {
          system = "aarch64-linux";
          specialArgs = {inherit inputs outputs;};
          modules = [
            ./nixosConfigurations/ponkila-ephemeral-gamma
            nixobolus.nixosModules.kexecTree
            nixobolus.nixosModules.homestakeros
            sops-nix.nixosModules.sops
            {
              nixpkgs.overlays = [
                nixobolus.overlays.default
                # Workaround for https://github.com/NixOS/nixpkgs/issues/154163
                # This issue only happens with the isoImage format
                (final: super: {
                  makeModulesClosure = x:
                    super.makeModulesClosure (x // {allowMissing = true;});
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
          specialArgs = {inherit inputs outputs;};
          modules = [
            ./nixosConfigurations/hetzner-ephemeral-alpha
            nixobolus.nixosModules.kexecTree
            nixobolus.nixosModules.homestakeros
            sops-nix.nixosModules.sops
            {
              nixpkgs.overlays = [
                nixobolus.overlays.default
              ];
              boot.loader.grub.enable = false;
            }
          ];
        };

        dinar-ephemeral-alpha = {
          system = "x86_64-linux";
          specialArgs = {inherit inputs outputs;};
          modules = [
            ./nixosConfigurations/dinar-ephemeral-alpha
            nixobolus.nixosModules.kexecTree
            nixobolus.nixosModules.homestakeros
            sops-nix.nixosModules.sops
            {
              nixpkgs.overlays = [
                nixobolus.overlays.default
              ];
              boot.loader.grub.enable = false;
            }
          ];
        };

        dinar-ephemeral-beta = {
          system = "x86_64-linux";
          specialArgs = {inherit inputs outputs;};
          modules = [
            ./nixosConfigurations/dinar-ephemeral-beta
            nixobolus.nixosModules.kexecTree
            nixobolus.nixosModules.homestakeros
            sops-nix.nixosModules.sops
            {
              nixpkgs.overlays = [
                nixobolus.overlays.default
              ];
              boot.loader.grub.enable = false;
            }
          ];
        };
      in {
        # NixOS configuration entrypoints
        nixosConfigurations = with nixpkgs.lib;
          {
            "dinar-ephemeral-alpha" = nixosSystem dinar-ephemeral-alpha;
            "dinar-ephemeral-beta" = nixosSystem dinar-ephemeral-beta;
            "hetzner-ephemeral-alpha" = nixosSystem hetzner-ephemeral-alpha;
            "ponkila-ephemeral-beta" = nixosSystem ponkila-ephemeral-beta;
          }
          // (with nixpkgs-stable.lib; {
            "ponkila-ephemeral-gamma" = nixosSystem ponkila-ephemeral-gamma;
          });
      };
    };
}
