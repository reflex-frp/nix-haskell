# The `preBuild` text that seeds a library build with compiled modules.
# `Setup build` then reads them, and ghc compiles only what it turns down.
# The epoch stamp keeps the restored files older than every source: Cabal
# reads times, though ghc itself reads hashes.
#
# The component definition outranks the package-level hook that haskell.nix
# would copy down, so `user-hook` re-includes it, first.
#
# Example:
#
#   import ./restore-intermediates.nix { inherit lib; } {
#     ghc = config.ghc.package;
#     pname = "frontend";
#     user-hook = null;
#     intermediates = builtins.outputOf plan.outPath "out";
#   }
#   => "mkdir -p dist\nrm -rf dist/build\ncp -r <plan out>/share/..."
{ lib }:

{ ghc, pname, user-hook, intermediates }:

let # Where the nixpkgs Haskell builders write and read intermediates, so
    # one tree serves either driver. The version is a glob: haskell.nix
    # states it only on plan-id entries, which not every writer of this
    # hook holds. A tree carries one build of the package, and `cp` fails
    # loudly on two matches.
    subdir = "share/haskell/${ghc.version}/${pname}-*/dist";

    restore = ''
      mkdir -p dist
      rm -rf dist/build
      cp -r ${intermediates}/${subdir}/build dist/build
      find dist/build -exec chmod u+w {} +
      find dist/build -exec touch -d '1970-01-01T00:00:00Z' {} +
    '';

in lib.optionalString (user-hook != null) (user-hook + "\n") + restore
