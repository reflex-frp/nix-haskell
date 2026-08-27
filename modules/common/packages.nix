# The `packages` option: per-package customization, keyed by cabal
# package name.
{ lib, packageFields, bundleOptimizerLayer, bundleOptimizersOption }:

with lib;
with (import ../../libs/prelude { inherit lib; });

{

  packages = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        src = mkOption {
          type = types.nullOr (types.either types.path types.package);
          default = null;
          description = ''
            Replacement source for the package.
          '';
          example = fenced-code ''./vendored/my-dep'';
        };
        previousIntermediates = mkOption {
          type = types.nullOr (types.either types.str types.package);
          default = null;
          description = ''
            Compiled modules of an earlier build to resume from: a path
            carrying `share/haskell/<ghc-version>/<pname>-<version>/dist/build`,
            which the build restores before `Setup build`. Modules ghc
            accepts are not compiled again. `fine-grained` sets this to a
            plan's output for the packages it selects, over a value set
            here.

            The nixpkgs driver builds a package as one derivation and
            restores the whole tree. The haskell.nix driver builds per
            component and restores the library's, the only component
            whose build the tree holds.
          '';
          example = fenced-code ''builtins.outputOf plan.outPath "out"'';
        };
        components = mkOption {
          type = types.submodule {
            options.exes = mkOption {
              type = types.attrsOf (types.submodule {
                options = {
                  inherit (bundleOptimizerLayer) wasm-opt closure-compiler;
                  bundle-optimizers = bundleOptimizersOption;
                };
              });
              default = {};
              description = ''
                Bundle optimizer settings for one executable of the
                package, keyed by the name cabal gives it. They sit under
                an executable rather than the package, because a bundle
                belongs to one linked executable. A package can carry
                several.

                Naming an executable here also tells the haskell.nix
                driver to install that executable's `.jsexe` directory,
                which it otherwise leaves in the build tree.
              '';
            };
          };
          default = {};
          description = ''
            Per-component customization, grouped by the component kind
            cabal uses. Only executables carry anything so far.
          '';
        };
        inherit (bundleOptimizerLayer) wasm-opt closure-compiler;
        bundle-optimizers = bundleOptimizersOption;
      } // packageFields.options;
    });
    default = {};
    description = ''
      Per-package customization, keyed by cabal package name. A driver
      ignores an entry for a package that is not in the final package
      set, and warns about nothing, so a platform-conditional package can
      be customized unconditionally.
    '';
    example = fenced-code ''
      {
        splitmix.patches = [ ./splitmix-js.patch ];
        reflex-dom-core.doCheck = false;
        my-app.flags.production = true;
      }
    '';
  };

}
