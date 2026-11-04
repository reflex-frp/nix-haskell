# A haskell.nix module that sets `nonReinstallablePkgs`. The build copies
# these packages from the compiler's package database. If a copied
# package needs a package that is not copied, the build fails.
#
# The list contains:
# 1. The haskell.nix list.
# 2. The packages that the compiler entry names.
# 3. If the project supplies the compiler, the packages that 1 and 2
#    need in its database. 1 and 2 already need these packages.
#
# A definition of the list replaces it rather than extends it. This module
# therefore reads haskell.nix's own definition and appends to it instead of
# restating it. That list depends on the compiler's version and on the
# target, and carries the packages a cross target's Template Haskell needs.
#
# The module goes into every project the driver builds, including the ones
# for the build platform, and decides per evaluation whether it applies.
# The compiler of the platform being built names the packages.
#
# Example:
#
#   import ./non-reinstallable.nix {
#     inherit lib compilers;
#     haskell-nix-src = config.inputs."haskell-nix";
#   }
#   => a haskell.nix module. For the wasm compiler of ghc-wasm-meta, it sets
#
#        config.nonReinstallablePkgs = [
#          "rts" "base" ... "filepath" ...     # 1. haskell.nix list
#          "system-cxx-std-lib"                # 2. compiler entry
#          "template-haskell-lift"             # 3. needed by 1 and 2
#          "template-haskell-quasiquoter" "pretty" "mtl"
#        ];
#
#      For a haskell.nix compiler that names no packages, it sets nothing.
{ lib, compilers, haskell-nix-src }:

{ pkgs, ... }@args:

let compiler = compilers.resolve (compilers.targetKey pkgs.stdenv.hostPlatform);

    upstream = import "${haskell-nix-src}/modules/install-plan/non-reinstallable.nix" args;

    roots = upstream.nonReinstallablePkgs ++ compiler.extraNonReinstallablePkgs;

    bootDependencies =
      if compiler.package == null
      then []
      else import ./boot-dependencies.nix { inherit lib pkgs; } {
        inherit (compiler) package targetPrefix;
        inherit roots;
      };

in {

  # This module must use mkIf, not a conditional body. `pkgs` reaches a
  # module through `_module.args`, so a module body that depends on `pkgs`
  # is a cycle.
  config = lib.mkIf (compiler.package != null || compiler.extraNonReinstallablePkgs != []) {
    nonReinstallablePkgs = roots ++ bootDependencies;
  };

}
