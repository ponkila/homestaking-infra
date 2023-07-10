{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        name = "init-qemu";
        init-qemu-script = (pkgs.writeScriptBin name (builtins.readFile ./init-qemu.sh)).overrideAttrs (old: {
          src = ./.;
          buildCommand = ''
            ${old.buildCommand}
            patchShebangs $out
          '';
        });
      in
      rec {
        packages.init-qemu = pkgs.symlinkJoin {
          name = name;
          paths = [ init-qemu-script ] ++ [ pkgs.qemu ];
          buildInputs = with pkgs; [ makeWrapper ];
          postBuild = "wrapProgram $out/bin/${name} --prefix PATH : $out/bin";
        };
        packages.default = packages.init-qemu;
      }
    );
}
