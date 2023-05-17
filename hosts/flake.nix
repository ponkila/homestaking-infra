{
  description = "Flake for aarch64 hosts";

  inputs = {
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    darwin.url = "github:lnl7/nix-darwin";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    ethereum-nix.inputs.nixpkgs.follows = "nixpkgs";
    ethereum-nix.url = "github:nix-community/ethereum.nix";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";
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
        "aarch64-darwin"
        "aarch64-linux"
      ];

      hetzner-ephemeral-beta = {
        system = "aarch64-linux";
        specialArgs = { inherit inputs outputs; };
        modules = [
          ./hosts/hetzner-ephemeral-beta
          ../system/formats/netboot-kexec.nix
          ../system/global.nix
          ../system/ramdisk.nix
          ../home-manager/juuso.nix
          ../home-manager/kari.nix
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
      };
    in
    rec {
      packages = forAllSystems (system: {
        hetzner-ephemeral-beta = nixosConfigurations.hetzner-ephemeral-beta.config.system.build.kexecTree;
      });

      nixosConfigurations = with nixpkgs.lib; {
        "hetzner-ephemeral-beta" = nixosSystem (getAttrs [ "system" "specialArgs" "modules" ] hetzner-ephemeral-beta);
      };

      herculesCI.ciSystems = [ "aarch64-linux" ];
    };
}
