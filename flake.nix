# https://xyno.space/post/nix-darwin-introduction
# https://github.com/Misterio77/nix-starter-configs/tree/main/standard
# https://sourcegraph.com/github.com/shaunsingh/nix-darwin-dotfiles@8ce14d457f912f59645e167707c4d950ae1c3a6e/-/blob/flake.nix
{

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
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    darwin.url = "github:lnl7/nix-darwin";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-23.05";
    nixobolus.url = "github:ponkila/nixobolus";
    mission-control.url = "github:Platonic-Systems/mission-control";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.05";
    pre-commit-hooks-nix.url = "github:hercules-ci/pre-commit-hooks.nix/flakeModule";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  # add the inputs declared above to the argument attribute set
  outputs =
    { self
    , darwin
    , disko
    , flake-parts
    , home-manager
    , nixobolus
    , nixpkgs
    , nixpkgs-stable
    , sops-nix
    , ...
    }@inputs:

    flake-parts.lib.mkFlake { inherit inputs; } rec {

      imports = [
        inputs.flake-root.flakeModule
        inputs.mission-control.flakeModule
        inputs.pre-commit-hooks-nix.flakeModule
      ];
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      perSystem = { pkgs, lib, config, system, ... }: {
        formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;

        pre-commit.settings = {
          hooks = {
            shellcheck.enable = true;
            nixpkgs-fmt.enable = true;
            flakecheck = {
              enable = true;
              name = "flakecheck";
              description = "Check whether the flake evaluates and run its tests";
              entry = "nix flake check --no-warn-dirty";
              language = "system";
              pass_filenames = false;
            };
          };
        };
        # Do not perform pre-commit hooks w/ nix flake check
        pre-commit.check.enable = false;

        mission-control.scripts = {
          nsq = {
            description = "Update and get the nix-store quaries.";
            exec = ''
              sh ./scripts/get-store-quaries.sh
            '';
            category = "Tools";
          };
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
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
          inputsFrom = [
            config.flake-root.devShell
            config.mission-control.devShell
          ];
          shellHook = ''
            ${config.pre-commit.installationScript}
          '';
        };

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
              ./hosts/ponkila-ephemeral-beta
              nixobolus.nixosModules.kexecTree
              nixobolus.nixosModules.homestakeros
              disko.nixosModules.disko
              sops-nix.nixosModules.sops
              {
                nixpkgs.overlays = [
                  outputs.overlays.additions
                  outputs.overlays.modifications
                ];
              }
              {
                boot.loader.systemd-boot.enable = true;
                boot.loader.efi.canTouchEfiVariables = true;
              }
            ];
          };

          ponkila-ephemeral-gamma = {
            system = "aarch64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./hosts/ponkila-ephemeral-gamma
              nixobolus.nixosModules.kexecTree
              nixobolus.nixosModules.homestakeros
              disko.nixosModules.disko
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
              ./hosts/hetzner-ephemeral-alpha
              ./modules/sys2x/gc.nix
              ./home-manager/juuso.nix
              ./home-manager/kari.nix
              nixobolus.nixosModules.kexecTree
              home-manager.nixosModules.home-manager
              {
                nixpkgs.overlays = [
                  outputs.overlays.additions
                  outputs.overlays.modifications
                ];
              }
              {
                boot.loader.systemd-boot.enable = true;
                boot.loader.efi.canTouchEfiVariables = true;
              }
            ];
          };

          hetzner-ephemeral-beta = {
            system = "aarch64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./hosts/hetzner-ephemeral-beta
              ./modules/sys2x/gc.nix
              ./home-manager/juuso.nix
              ./home-manager/kari.nix
              nixobolus.nixosModules.kexecTree
              home-manager.nixosModules.home-manager
              {
                nixpkgs.overlays = [
                  outputs.overlays.additions
                  outputs.overlays.modifications
                ];
              }
              {
                boot.loader.systemd-boot.enable = true;
                boot.loader.efi.canTouchEfiVariables = true;
              }
            ];
          };

          dinar-ephemeral-alpha = {
            system = "x86_64-linux";
            specialArgs = { inherit inputs outputs; };
            modules = [
              ./hosts/dinar-ephemeral-alpha
              nixobolus.nixosModules.isoImage
              nixobolus.nixosModules.homestakeros
              disko.nixosModules.disko
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
              ./hosts/dinar-ephemeral-beta
              nixobolus.nixosModules.isoImage
              nixobolus.nixosModules.homestakeros
              disko.nixosModules.disko
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

          overlays = import ./overlays { inherit inputs; };

          nixosConfigurations = with nixpkgs.lib; {
            "dinar-ephemeral-alpha" = nixosSystem dinar-ephemeral-alpha;
            "hetzner-ephemeral-alpha" = nixosSystem hetzner-ephemeral-alpha;
            "dinar-ephemeral-beta" = nixosSystem dinar-ephemeral-beta;
            "ponkila-ephemeral-beta" = nixosSystem ponkila-ephemeral-beta;
          } // (with nixpkgs-stable.lib; {
            "hetzner-ephemeral-beta" = nixosSystem hetzner-ephemeral-beta;
            "ponkila-ephemeral-gamma" = nixosSystem ponkila-ephemeral-gamma;
          });

          darwinConfigurations."ponkila-persistent-epsilon" = darwin.lib.darwinSystem {
            specialArgs = { inherit inputs outputs; };
            system = "x86_64-darwin";
            modules = [
              ./hosts/ponkila-persistent-epsilon/default.nix
            ];
          };
        };
    };
}
