{ system ? builtins.currentSystem
, inputs ? import ./inputs.nix
}:

let project = import ./default.nix { inherit system inputs; };

in {
  haskell-nix = project.haskell-nix.shell;
  nixpkgs = project.nixpkgs.shell;

  haskell-nix-wasm-meta = project.haskell-nix-wasm-meta.shell;
  nixpkgs-wasm-meta = project.nixpkgs-wasm-meta.shell;
}
