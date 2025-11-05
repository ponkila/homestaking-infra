{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    devenv.url = "github:cachix/devenv";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = { ... }@inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    systems = inputs.nixpkgs.lib.systems.flakeExposed;
    perSystem = { pkgs, ... }: {
      devShells.default = inputs.devenv.lib.mkShell {
        inherit inputs pkgs;
        modules = [{
          # https://devenv.sh/reference/options/
          packages = with pkgs; [
            gnumake
            gotestsum
            jq
            protobuf
            protoc-gen-go
          ];
          languages = {
            go.enable = true;
            javascript = {
              enable = true;
              npm.enable = true;
            };
          };
        }];
      };
    };
  };
}
