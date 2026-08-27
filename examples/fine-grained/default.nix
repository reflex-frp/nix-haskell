# Build the library one module at a time, under either driver.
#
# Evaluation reads `builtins.outputOf`, and the builds need the
# `builder-rpc-v0` system feature. A stock daemon does neither, so `run`
# carries a Nix that does both and drives a store of its own. Set
# `FINE_GRAINED_STORE` to put that store somewhere else.
#
#   nix-build examples/fine-grained -A run
#   ./result/bin/fine-grained-nix build -f examples/fine-grained library-nixpkgs
#   ./result/bin/fine-grained-nix build -f examples/fine-grained library-haskell-nix
{ system ? builtins.currentSystem, inputs ? {} }:

let nix-haskell = import ../../default.nix { inherit system inputs; };

    project = nix-haskell (import ./project.nix);

    pkgs = project.pkgs;

    nix = project.config.fine-grained.nix;

in {

  inherit nix;

  library-nixpkgs = project.nixpkgs.project.packages.fine-grained;

  library-haskell-nix = project.haskell-nix.project.hsPkgs.fine-grained.components.library;

  # A machine's configuration names paths that only its daemon reads, its
  # binfmt registrations and its signing key among them, so this starts from
  # the Nix defaults. Its store still fills the one below, by copy.
  run = pkgs.writeShellScriptBin "fine-grained-nix" ''
    export NIX_CONF_DIR=${pkgs.emptyDirectory}
    export NIX_USER_CONF_FILES=

    exec ${nix}/bin/nix \
      --store "''${FINE_GRAINED_STORE:-/tmp/nix-haskell-fine-grained}" \
      --substituters 'daemon?trusted=1 https://cache.nixos.org' \
      --extra-experimental-features 'nix-command ca-derivations dynamic-derivations' \
      --extra-system-features builder-rpc-v0 \
      "$@"
  '';

}
