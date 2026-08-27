# Build the library one module at a time, under either driver.
#
# Evaluation reads `builtins.outputOf`, and the builds need the
# `builder-rpc-v0` system feature. A stock daemon does neither, so `run`
# carries a Nix that does both and drives a store of its own. Set
# `NIX_DYNAMIC_DRV_STORE` to put that store somewhere else.
#
#   nix-build examples/fine-grained -A run
#   ./result/bin/fine-grained-nix build -f examples/fine-grained library-nixpkgs
#   ./result/bin/fine-grained-nix build -f examples/fine-grained library-haskell-nix
{ system ? builtins.currentSystem, inputs ? {} }:

let nix-haskell = import ../../default.nix { inherit system inputs; };

    project = nix-haskell (import ./project.nix);

in {

  inherit (project.config.fine-grained) nix run;

  library-nixpkgs = project.nixpkgs.project.packages.fine-grained;

  library-haskell-nix = project.haskell-nix.project.hsPkgs.fine-grained.components.library;

}
