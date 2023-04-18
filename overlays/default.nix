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
      # Enables aggressive optimisations including full LTO
      PROFILE = "maxperf";
    });
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
    # });
  };
}
