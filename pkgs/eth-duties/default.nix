# Change to this after debug
# { lib
# , pkgs
# , poetry2nix
# , fetchFromGitHub
# }:

{ pkgs ? import <nixpkgs> { }
, lib ? pkgs.lib
, poetry2nix ? pkgs.poetry2nix
, fetchFromGitHub ? pkgs.fetchFromGitHub
}:
let
  pname = "eth-duties";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "TobiWo";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-CuAbNloZEUMr6nlqk6KG9wqmAD6mPnZ4Xwnv/wpZ70U=";
  };

  python = pkgs.python310;
  python_slim = python.override {
    mimetypesSupport = false;
    x11Support = false;
    stripConfig = true;
    stripIdlelib = true;
    stripTests = true;
    stripTkinter = true;
    rebuildBytecode = true;
    stripBytecode = true;
    includeSiteCustomize = false;
    enableOptimizations = false;
    bzip2 = null;
    #expat = null;
    #libffi = null;
    gdbm = null;
    xz = null;
    ncurses = null;
    #openssl = null;
    readline = null;
    sqlite = null;
    #zlib = null;
    tzdata = null;
  };
in poetry2nix.mkPoetryApplication rec {

  # postPatch = ''
  #   export HOME=$NIX_BUILD_TOP
  # '';

  projectDir = src;
  python = python_slim;
  #preferWheels = true;

  # https://github.com/nix-community/poetry2nix/blob/master/docs/edgecases.md
  overrides = poetry2nix.defaultPoetryOverrides.extend (self: super: {
    dataclass-wizard = super.dataclass-wizard.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [super.setuptools];
    });
    isort = super.isort.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [super.poetry];
    });
    altgraph = super.altgraph.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [super.setuptools];
    });
    pathspec = super.pathspec.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [super.flit-core];
    });
    pyinstaller-hooks-contrib = super.pyinstaller-hooks-contrib.overridePythonAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [super.setuptools];
    });
    # pyinstaller = super.pyinstaller.overridePythonAttrs (old: {
    #   buildInputs = (old.buildInputs or []) ++ [pkgs.zlib];
    # });
    # eth-duties = super.eth-duties.overridePythonAttrs (old: {
    #   buildInputs = (old.buildInputs or []) ++ [super.poetry-core];
    # });
  });
  
  meta = with lib; {
    homepage = "https://github.com/TobiWo/eth-duties";
    description = "Tool for logging upcoming validator duties to the console";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
