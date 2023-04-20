{ inputs, ... }:
{
  # Adds custom packages
  additions = final: _prev: import ../pkgs { pkgs = final; };

  # Modifies existing packages
  modifications = final: prev: {
    lighthouse = prev.lighthouse.overrideAttrs (oldAttrs: rec {
      # Enables aggressive optimisations including full LTO
      PROFILE = "maxperf";
    });
  };
}
