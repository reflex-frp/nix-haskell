# The files nix-haskell imports from inside its inputs, keyed by input.
# The `upstream-paths` check fails when a bump moves one, and names it.
#
# Example:
#
#   "${inputs.haskell-nix}/${(import ./upstream-paths.nix).haskell-nix.host-map}"
#   => "<haskell.nix>/lib/host-map.nix"
{
  haskell-nix = {
    cabal-project = "modules/cabal-project.nix";
    cabal-project-parser = "lib/cabal-project-parser.nix";
    host-map = "lib/host-map.nix";
    non-reinstallable = "modules/install-plan/non-reinstallable.nix";
    project = "modules/project.nix";
    project-common = "modules/project-common.nix";
  };

  ghc-wasm-meta = {
    wasi-sdk = "pkgs/wasi-sdk.nix";
    wasm32-wasi-ghc = "pkgs/wasm32-wasi-ghc.nix";
  };
}
