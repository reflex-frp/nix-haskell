# Everything to build before a release: the repo's own checks, and the
# reflex-todomvc example across every driver, compiler and cross target it
# is meant to work for. The example is built two ways: as the drivers build
# it, and as a person would inside the project's shell.
#
# A stock Nix builds every attribute here. The fine-grained example's
# libraries need one carrying dynamic derivations, so they appear only
# there, and `fine-grained.run` builds them on any other machine.
#
#   nix-build release.nix -A all
#   nix-build release.nix -A checks
#   nix-build release.nix -A reflex-todomvc.build.haskell-nix.ghc912.wasi32
#   nix-build release.nix -A fine-grained.run
#
# `all` is a directory of symlinks to every other attribute, so one build
# realises everything and names what it realised.
{ system ? builtins.currentSystem, inputs ? {} }:

let pkgs = (import ./default.nix { inherit system inputs; } {}).pkgs;

    inherit (pkgs) lib;

    # Every derivation in a tree of attribute sets, named by its path. The
    # path is also where it lands in `all`. The `recurseForDerivations`
    # markers only guide `nix-build` and are not entries.
    entries = prefix: value:
      let childName = name:
            if prefix == ""
            then name
            else "${prefix}/${name}";
          children = removeAttrs value [ "recurseForDerivations" ];
      in if lib.isDerivation value
         then [ { name = prefix; path = value; } ]
         else lib.concatLists (lib.mapAttrsToList
           (name: entry: entries (childName name) entry)
           children);

    released = {

      checks = import ./tests { inherit system inputs; };

      reflex-todomvc = import ./examples/reflex-todomvc/release.nix {
        inherit system inputs;
      };

      # The tool and the wrapper build anywhere. The libraries read
      # `builtins.outputOf`, so they join them only where the Nix reading
      # this carries dynamic derivations, and the wrapper builds them
      # anywhere else.
      fine-grained =
        let example = import ./examples/fine-grained { inherit system inputs; };
        in { inherit (example) nix run; }
           // lib.optionalAttrs (builtins ? outputOf) {
             inherit (example) library-nixpkgs library-haskell-nix;
           };

    };

in released // {

  all = pkgs.linkFarm "nix-haskell-release" (entries "" released);

}
