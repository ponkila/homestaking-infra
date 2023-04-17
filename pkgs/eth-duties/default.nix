{ pkgs ? import <nixpkgs> { }
, lib ? pkgs.lib
, poetry2nix ? pkgs.poetry2nix
, fetchFromGitHub ? pkgs.fetchFromGitHub
}:

poetry2nix.mkPoetryApplication rec {
  pname = "eth-duties";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "TobiWo";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-CuAbNloZEUMr6nlqk6KG9wqmAD6mPnZ4Xwnv/wpZ70U=";
  };

  projectDir = src;

  # https://github.com/nix-community/poetry2nix/blob/master/docs/edgecases.md
  overrides = poetry2nix.defaultPoetryOverrides.extend (self: super: {
    dataclass-wizard = super.dataclass-wizard.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [super.setuptools];
    });
    altgraph = super.altgraph.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [super.setuptools];
    });
    poetry-core = super.poetry-core.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [super.poetry-core];
    });
    isort = super.isort.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [super.poetry];
    });
    tomlkit = super.tomlkit.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [super.poetry];
    });
    pathspec = super.pathspec.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [super.flit-core];
    });
    pyinstaller = super.pyinstaller.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [pkgs.zlib];
    });
    pyinstaller-hooks-contrib = super.pyinstaller-hooks-contrib.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [super.setuptools];
    });
  });

  meta = with lib; {
    homepage = "https://github.com/TobiWo/eth-duties";
    description = "Tool for logging upcoming validator duties to the console";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}

