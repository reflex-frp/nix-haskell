# DO NOT HAND-EDIT THIS FILE
{
  inputs = {
    "upstream" = {
      owner = "haskell-wasm";
      repo = "ghc-wasm-meta";
      rev = "8079eb96bbc63823d99ad8acaff0765532625474";
      type = "github";
      inputs = {
        "flake-utils" = { follows = "flake-utils"; };
        "nixpkgs" = { follows = "nixpkgs"; };
      };
    };
    "flake-utils" = {
      narHash = "sha256-l0KFg5HjrsfsO/JpG+r7fRrqm12kzFHyUHqHCVpMMbI=";
      owner = "numtide";
      repo = "flake-utils";
      rev = "11707dc2f618dd54ca8739b309ec4fc024de578b";
      type = "github";
      inputs = {
        "systems" = { follows = "systems"; };
      };
    };
    "nixpkgs" = {
      narHash = "sha256-cy5PsNucfXU5+KtLR+S9/zdkWOUplhL5Xr0LQWhSYbs=";
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "2bd3427b41d10b8318383195efe502ed1baca6cd";
      type = "github";
    };
    "systems" = {
      narHash = "sha256-Vy1rq5AaRuLzOxct8nz4T6wlgyUR7zLU309k9mBC768=";
      owner = "nix-systems";
      repo = "default";
      rev = "da67096a3b9bf56a91d16901293e51ba5b49a27e";
      type = "github";
    };
  };
  outputs = inputs: inputs."upstream".outputs // { src = inputs."upstream"; };
}
