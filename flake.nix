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
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
    nixos-generators.url = "github:nix-community/nixos-generators";
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
    , nixos-generators
    , nixpkgs
    , sops-nix
    }@inputs:

    let
      inherit (self) outputs;
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      # custom formats for nixos-generators
      customFormats = {
        "kexecTree" = {
          formatAttr = "kexecTree";
          imports = [ ./system/netboot.nix ];
        };
        "copytoram-iso" = {
          formatAttr = "isoImage";
          imports = [ ./system/copytoram-iso.nix ];
          filename = "*.iso";
        };
      };
    in
    {

      formatter = forAllSystems (system:
        nixpkgs.legacyPackages.${system}.nixpkgs-fmt
      );

      overlays = import ./overlays { inherit inputs; };

      # Your custom packages
      # Acessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in import ./pkgs { inherit pkgs; }
      );

      "ponkila-ephemeral-beta" = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        specialArgs = { inherit inputs outputs; };
        modules = [
          ./hosts/ponkila-ephemeral-beta
          ./hosts/ponkila-ephemeral-beta/mounts.nix
          ./modules/eth/erigon.nix
          ./modules/eth/lighthouse-beacon.nix
          ./modules/eth/mev-boost.nix
          ./system/global.nix
          ./system/ramdisk.nix
          ./home-manager/core.nix
          home-manager.nixosModules.home-manager
          disko.nixosModules.disko
          ({ pkgs, ... }: {
            nixpkgs.overlays = [ ethereum-nix.overlays.default ];
          })
          {
            home-manager.sharedModules = [
              sops-nix.homeManagerModules.sops
            ];
          }
        ];
        customFormats = customFormats;
        format = "kexecTree";
      };

      "dinar-ephemeral-alpha" = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        specialArgs = { inherit inputs outputs; };
        modules = [
          ./hosts/dinar-ephemeral-alpha
          ./hosts/dinar-ephemeral-alpha/mounts.nix
          ./modules/eth/erigon.nix
          ./modules/eth/lighthouse-beacon.nix
          ./modules/eth/mev-boost.nix
          ./system/global.nix
          ./home-manager/core.nix
          home-manager.nixosModules.home-manager
          disko.nixosModules.disko
          ({ pkgs, ... }: {
            nixpkgs.overlays = [ ethereum-nix.overlays.default ];
          })
          {
            home-manager.sharedModules = [
              sops-nix.homeManagerModules.sops
            ];
          }
        ];
        customFormats = customFormats;
        format = "copytoram-iso";
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

    };
}
