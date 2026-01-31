{ stdenv
, fetchFromGitHub
, ...
}:
stdenv.mkDerivation rec {
  name = "awesome-prometheus-alerts";
  src = fetchFromGitHub {
    owner = "samber";
    repo = name;
    rev = "f0107caf9efad8edecbe41e1f1e4f1dd4a8f6dab";
    sha256 = "sha256-dSPSXpWpTY7jjFWLvHMefvuWIvzXADt4XTVALjkWxdk=";
  };

  installPhase = ''
    mkdir -p "$out"
    cp -r dist/rules/* $out
  '';
}
