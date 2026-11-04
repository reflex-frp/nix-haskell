# Resolves one shell tool to the package that provides it: the first of
# the given sources that carries the name. A version request needs a
# solver to honor, so this ignores `request`.
#
# Example:
#
#   resolve = import ./resolve-shell-tool.nix { inherit lib; };
#
#   resolve {
#     name = "cabal";
#     request = "latest";
#     tool-packages = {};
#     inherit pkgs;
#     haskellPackages = hp;
#   }
#   => pkgs.cabal
#
#   resolve { name = "hpack2nix"; request = null; tool-packages = {}; inherit pkgs; haskellPackages = hp; }
#   => throws: nix-haskell (nixpkgs driver): cannot find the shell tool
#      "hpack2nix"; set nixpkgs.options.tool-packages."hpack2nix"
{ lib }:

{ name, request, tool-packages, pkgs, haskellPackages }:

with (import ../common { inherit lib; });

let prefix = message-prefix { driver = "nixpkgs"; };

    sources = [ tool-packages pkgs haskellPackages ];

    found = lib.findFirst (set: set ? ${name}) null sources;

in if found == null
   then throw (prefix "cannot find the shell tool \"${name}\"; set nixpkgs.options.tool-packages.\"${name}\"")
   else found.${name}
