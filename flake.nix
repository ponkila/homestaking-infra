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
    nixobolus.url = "github:ponkila/nixobolus/juuso/options-extractions";
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
    , nixobolus
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

      ponkila-ephemeral-beta = {
        system = "x86_64-linux";
        specialArgs = { inherit inputs outputs; };
        modules = [
          ./home-manager/core.nix
          ./hosts/ponkila-ephemeral-beta
          ./system/global.nix
          ./system/ramdisk.nix
          home-manager.nixosModules.home-manager
          disko.nixosModules.disko
          nixobolus.nixosModules.erigon
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
        customFormats = customFormats;
        format = "kexecTree";
      };

      dinar-ephemeral-alpha = {
        format = "install-iso";
        system = "x86_64-linux";
        specialArgs = { inherit inputs outputs; };
        modules = [
          ./home-manager/core.nix
          ./hosts/dinar-ephemeral-alpha
          ./hosts/dinar-ephemeral-alpha/mounts.nix
          ./system/global.nix
          home-manager.nixosModules.home-manager
          disko.nixosModules.disko
          nixobolus.nixosModules.erigon
          nixobolus.nixosModules.lighthouse
          nixobolus.nixosModules.mev-boost
          nixobolus.nixosModules.mounts
          nixobolus.nixosModules.localization
          nixobolus.nixosModules.user
          nixobolus.nixosModules.ssh
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
          {
            # GRUB timeout
            boot.loader.timeout = nixpkgs.lib.mkForce 1;

            # Load into a tmpfs during stage-1
            boot.kernelParams = [ "copytoram" ];
          }
        ];
      };
    in
    {

      # To run:
      # $ nix fmt
      formatter = forAllSystems (system:
        nixpkgs.legacyPackages.${system}.nixpkgs-fmt
      );

      overlays = import ./overlays { inherit inputs; };

      # Your custom packages
      # Acessible through 'nix build', 'nix shell', etc
      #
      # E.g., to build one image:
      # nix build .#dinar-ephemeral-alpha
      #
      packages = forAllSystems (system: {
        dinar-ephemeral-alpha = nixos-generators.nixosGenerate dinar-ephemeral-alpha;
        ponkila-ephemeral-beta = nixos-generators.nixosGenerate ponkila-ephemeral-beta;
      });

      # Despite defining the hosts here, the rebuild command is not supposed to used:
      # instead, these are defined here to make use of standard tools to read config
      # declarations of each host, and to verify all images are bootable (nix flake check)
      #
      # E.g., to read lighthouse endpoint IP:
      # $ nix eval .#nixosConfigurations.dinar-ephemeral-alpha.config.lighthouse.endpoint
      #
      # To hack and explore the configuration:
      # NOTE: repl-flakes does *not* work: https://github.com/NixOS/nix/issues/8059
      # $ nix repl
      # nix-repl> :lf .#
      # nix-repl> (press TAB for autocomplete)
      #
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

    };
}
