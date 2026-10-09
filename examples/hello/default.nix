# Build with either driver:
#   nix-build -A nixpkgs.packages.hello
#   nix-build -A haskell-nix.hsPkgs.hello.components.exes.hello
{ system ? builtins.currentSystem
, inputs ? import ../../inputs.nix
}:

let nix-haskell = import ../../default.nix { inherit system inputs; };
    project = nix-haskell (import ./project.nix);
in {
  nixpkgs = project.nixpkgs.project;
  haskell-nix = project.haskell-nix.project;
}
