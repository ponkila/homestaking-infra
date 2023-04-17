# This file defines overlays
{ inputs, ... }:
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs { pkgs = final; };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = super: prev: with super.lib; {
    lighthouse = prev.lighthouse.overrideAttrs (old: rec {
      version = "4.0.2-rc.0";
      src = super.fetchFromGitHub {
        owner = "sigp";
        repo = "lighthouse";
        rev = "v${version}";
        # If you don't know the hash, the first time, set:
        # sha256 = "0000000000000000000000000000000000000000000000000000";
        sha256 = "sha256-10DpoG9MS6jIod0towzIsmyyakfiT62NIJBKxqsgsK0=";
      };
      # Enables aggressive optimisations including full LTO
      PROFILE = "maxperf";

      cargoHash = "sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=";

    });
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
    # });
  };
}
