# The base Haskell package set for a resolved compiler entry, out of a
# nixpkgs package set. A named compiler selects `haskell.packages.<name>`.
# A compiler package replaces the `ghc` of the set that matches it most
# closely:
# 1. The set of its own major.minor.patch.
# 2. The set it names.
# 3. Whatever the package set offers by default.
# The closest set matters because everything outside the project is built
# from it, so its bounds and its boot libraries should be the ones the
# compiler was built with.
#
# Example:
#
#   import ./haskell-packages.nix { inherit lib pkgs; compiler = <entry>; }
#   => <pkgs.haskell.packages.ghc9124 with the bindist as its ghc>, for an entry
#      whose package is a 9.12.4 bindist named ghc912
#   => pkgs.haskell.packages.ghc912, for an entry with a name and no package
#   => a throw naming the ghc* sets this nixpkgs does have, for a name it has
#      none of
{ lib, pkgs, compiler }:

with lib;

with (import ../common { inherit lib; });

let prefix = message-prefix { driver = "nixpkgs"; };

    closestSet =
      pkgs.haskell.packages.${compiler.stockName}
      or pkgs.haskell.packages.${compiler.name}
      or pkgs.haskellPackages;

    replacingGhc = closestSet.override { ghc = compiler.annotated; };

    availableGhcSets = concatStringsSep ", "
      (filter (hasPrefix "ghc") (attrNames pkgs.haskell.packages));

    noSuchSet = throw (prefix ("haskell.packages for"
      + " ${pkgs.stdenv.hostPlatform.system} has no \"${compiler.name}\""
      + " (available: ${availableGhcSets});"
      + " set nixpkgs.compiler.name or nixpkgs.haskellPackages"));

    namedSet = pkgs.haskell.packages.${compiler.name} or noSuchSet;

in if compiler.annotated != null
   then replacingGhc
   else namedSet
