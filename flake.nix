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
    ethereum-nix.inputs.nixpkgs.follows = "nixpkgs";
    ethereum-nix.url = "github:nix-community/ethereum.nix";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  # add the inputs declared above to the argument attribute set
  outputs =
    { self
    , darwin
    , disko
    , ethereum-nix
    , home-manager
    , nixpkgs
    , sops-nix
    }@inputs:

    let
      inherit (self) outputs;
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      ponkila-ephemeral-beta = {
        system = "x86_64-linux";
        specialArgs = { inherit inputs outputs; };
        modules = [
          ./hosts/ponkila-ephemeral-beta
          ./modules/eth/erigon.nix
          ./modules/eth/lighthouse-beacon.nix
          ./modules/eth/mev-boost.nix
          ./system/formats/netboot-kexec.nix
          ./system/global.nix
          ./system/ramdisk.nix
          ./home-manager/core.nix
          home-manager.nixosModules.home-manager
          disko.nixosModules.disko
          {
            nixpkgs.overlays = [
              ethereum-nix.overlays.default
              outputs.overlays.additions
              outputs.overlays.modifications
            ];
          }
          {
            home-manager.sharedModules = [
              sops-nix.homeManagerModules.sops
            ];
          }
        ];
      };

      hetzner-ephemeral-alpha = {
        system = "x86_64-linux";
        specialArgs = { inherit inputs outputs; };
        modules = [
          ./hosts/hetzner-ephemeral-alpha
          ./system/global.nix
          ./system/ramdisk.nix
          ./home-manager/juuso.nix
          ./home-manager/kari.nix
          home-manager.nixosModules.home-manager
          {
            nixpkgs.overlays = [
              outputs.overlays.additions
              outputs.overlays.modifications
            ];
          }
          {
            home-manager.sharedModules = [
              sops-nix.homeManagerModules.sops
            ];
          }
        ];
        customFormats = customFormats;
        format = "kexecTree";
      };

      dinar-ephemeral-alpha = {
        system = "x86_64-linux";
        specialArgs = { inherit inputs outputs; };
        modules = [
          ./hosts/dinar-ephemeral-alpha
          ./modules/eth/erigon.nix
          ./modules/eth/lighthouse-beacon.nix
          ./modules/eth/mev-boost.nix
          ./system/formats/copytoram-iso.nix
          ./system/global.nix
          ./home-manager/core.nix
          home-manager.nixosModules.home-manager
          disko.nixosModules.disko
          {
            nixpkgs.overlays = [
              ethereum-nix.overlays.default
              outputs.overlays.additions
              outputs.overlays.modifications
            ];
          }
          {
            home-manager.sharedModules = [
              sops-nix.homeManagerModules.sops
            ];
          }
        ];
      };
    in
    rec {

      formatter = forAllSystems (system:
        nixpkgs.legacyPackages.${system}.nixpkgs-fmt
      );

      overlays = import ./overlays { inherit inputs; };

      packages = forAllSystems (system: {
        dinar-ephemeral-alpha = nixosConfigurations.dinar-ephemeral-alpha.config.system.build.isoImage;
        ponkila-ephemeral-beta = nixosConfigurations.ponkila-ephemeral-beta.config.system.build.kexecTree;
      });

      nixosConfigurations = with nixpkgs.lib; {
        "dinar-ephemeral-alpha" = nixosSystem (getAttrs [ "system" "specialArgs" "modules" ] dinar-ephemeral-alpha);
        "ponkila-ephemeral-beta" = nixosSystem (getAttrs [ "system" "specialArgs" "modules" ] ponkila-ephemeral-beta);
      };

      darwinConfigurations."ponkila-persistent-epsilon" = darwin.lib.darwinSystem {
        specialArgs = { inherit inputs outputs; };
        system = "x86_64-darwin";
        modules = [
          ./hosts/ponkila-persistent-epsilon/default.nix
        ];
      };

      # Devshell for bootstrapping
      # Acessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = forAllSystems
        (system:
          let pkgs = nixpkgs.legacyPackages.${system};
          in import ./shell.nix { inherit pkgs; }
        );

      herculesCI.ciSystems = [ "x86_64-linux" ];
    };

}
