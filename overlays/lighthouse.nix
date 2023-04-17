self: super: with super.lib; {
  lighthouse = super.lighthouse.overrideAttrs (old: rec {
    pname = "lighthouse";
    version = "4.0.2-rc.0";
    src = super.fetchFromGitHub {
      owner = "sigp";
      repo = pname;
      rev = "v${version}";
      # If you don't know the hash, the first time, set:
      # sha256 = "0000000000000000000000000000000000000000000000000000";
      sha256 = lib.fakeHash;
    };
    # Enables aggressive optimisations including full LTO
    PROFILE = "maxperf";
  });
}