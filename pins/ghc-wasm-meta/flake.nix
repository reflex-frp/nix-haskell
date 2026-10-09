# DO NOT HAND-EDIT THIS FILE
{
  inputs = {
    "upstream" = {
      owner = "haskell-wasm";
      repo = "ghc-wasm-meta";
      rev = "5b96779e3d356b3962b6e9c85a9db3a1fcc31ed1";
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
      narHash = "sha256-rdJdWxAcg5fnntU4DjPivPdVEN4F+VJavw+UWpEMeUI=";
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "329c3d2af6d1b618705150ea39f72c15eb4e613e";
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
