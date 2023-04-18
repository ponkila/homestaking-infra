# This file defines overlays
{ inputs, ... }:
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs { pkgs = final; };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  # final: # package set with all overlays applied, a "fixed" point
  # prev: # state of the package set before applying this overlay
  modifications = final: prev: {
    lighthouse = prev.lighthouse.overrideAttrs (oldAttrs: rec {
      # Enables aggressive optimisations including full LTO
      PROFILE = "maxperf";
    });
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
    # });
  };
}
