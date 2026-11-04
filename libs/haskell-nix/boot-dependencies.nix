# The packages that `roots` need in the global package database of a
# compiler, without `roots` themselves. `ghc-pkg` reads the database, so
# this file does not need to know where the compiler keeps it.
#
# Example:
#
#   import ./boot-dependencies.nix { inherit lib pkgs; } {
#     package = <wasm32-wasi-ghc-9.14 of ghc-wasm-meta>;
#     targetPrefix = "wasm32-wasi-";
#     roots = [ "template-haskell" ];
#   }
#   => [ "base" "ghc-boot-th" "ghc-internal" "ghc-prim" "pretty" "rts" "deepseq" ]
#
#   The same call with roots = [ "rts" ]
#   => [ ]
{ lib, pkgs }:

{ package, targetPrefix, roots }:

let fields = pkgs.buildPackages.runCommand "${package.name}-boot-packages" {} ''
      ${package}/bin/${targetPrefix}ghc-pkg field --global --simple-output '*' name,id,depends > $out
    '';

    text = builtins.readFile fields;

    lines = lib.splitString "\n" (lib.removeSuffix "\n" text);

    words = line: builtins.filter (word: word != "") (lib.splitString " " line);

    # ghc-pkg writes three lines for each package: name, id, depends.
    packages = lib.genList (i: {
      name = builtins.elemAt lines (3 * i);
      id = builtins.elemAt lines (3 * i + 1);
      depends = words (builtins.elemAt lines (3 * i + 2));
    }) (builtins.length lines / 3);

    nameOf = builtins.listToAttrs (map (p: lib.nameValuePair p.id p.name) packages);

    dependsOf = lib.mapAttrs
      (_: versions: lib.concatMap (p: map (id: nameOf.${id}) p.depends) versions)
      (lib.groupBy (p: p.name) packages);

    closure = builtins.genericClosure {
      startSet = map (name: { key = name; }) roots;
      operator = item: map (name: { key = name; }) (dependsOf.${item.key} or []);
    };

in lib.subtractLists roots (map (item: item.key) closure)
