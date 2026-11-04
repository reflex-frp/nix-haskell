# The `platforms` option: per-platform customization, carrying the
# project-wide `packages` option itself (merged in as a declaration, not
# copied) with the driver-built `bundles` added.
{ lib, packages, bundleFields, bundleOptimizerLayer, bundleOptimizersOption }:

with lib;
with (import ../../libs/common { inherit lib; });

{

  platforms = mkOption {
    type =
      let platformPackageModule = platform: { config, name, ... }:
            let package = name;
                entry = config;
                exeBundles = exe: bundleFields { inherit platform package exe; };
            in {
              options.bundles = mkOption {
                type = types.attrsOf (types.submodule ({ name, ... }:
                  { options = exeBundles name; }));
                default = genAttrs (attrNames entry.components.exes) (_: {});
                defaultText = literalMD ''
                  one entry per executable named under `components.exes`
                '';
                description = ''
                  What this package's executables are shipped as for this
                  target, keyed by the name each carries in
                  `components.exes`. The whole set can be read at once,
                  without naming each executable again.
                '';
              };

              options.components = mkOption {
                type = types.submodule {
                  options.exes = mkOption {
                    type = types.attrsOf (types.submodule ({ name, ... }:
                      { options.bundles = exeBundles name; }));
                  };
                };
              };
            };

          # The project-wide `packages` option, with the platform's fields
          # merged in as a declaration, not as a second copy.
          platformPackagesOption = platform: packages // {
            type = types.attrsOf (types.submoduleWith {
              shorthandOnlyDefinesConfig = true;
              modules = packages.type.nestedTypes.elemType.getSubModules ++ [
                (platformPackageModule platform)
              ];
            });
            description = ''
              Per-package customization for this platform only, merged
              over the project-wide `packages`. The fields are the same,
              with `bundles` added: what a driver built for this target,
              in the form that ships.
            '';
          };

          platformModule = { name, ... }:
            let platform = name;
            in {
              options = {
                packages = platformPackagesOption platform;
                inherit (bundleOptimizerLayer) wasm-opt closure-compiler;
                bundle-optimizers = bundleOptimizersOption;
              };
            };

      in types.attrsOf (types.submodule platformModule);
    default = {};
    description = ''
      Per-platform customization, keyed by `pkgs.pkgsCross` platform name
      (the keys of `shell.crossPlatforms` and `projectCross`).

      A cabal file or project file can make a package's flags, and through
      them its dependencies, conditional on the platform. Each driver
      handles that differently:

      - haskell.nix follows those conditionals through its solver
      - nixpkgs has no solver, so state here what the conditionals would
        have decided

      The flags reach the point where a package's dependencies are
      computed, not only its configuration.

      `wasm-opt` and `closure-compiler` are the bundle optimizer settings
      for whatever is built for this target. The `packages` entries under
      them narrow a setting to one package, and their `components.exes`
      entries to one executable of it.
    '';
    example = fenced-code ''
      {
        wasi32.wasm-opt.level = "z";
        wasi32.packages.reflex-dom.flags.use-warp = false;
      }
    '';
  };

}
