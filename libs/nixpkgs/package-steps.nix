# The per-package tweak steps: one `drv -> drv` function per stated field
# of a `packages` entry, in application order. `generated` says whether
# cabal2nix generated the package expression. If it did, cabal2nix already
# applied the package's cabal flags, so these steps do not toggle them
# again. `compose` is the `haskell.lib.compose` of the package set's own
# nixpkgs. `name` is unused here. It is part of the call so a replacement
# can vary the steps per package.
#
# Example:
#
#   steps = import ./package-steps.nix { inherit lib; };
#
#   lib.pipe drv (steps {
#     name = "reflex-dom";
#     tweaks = config.nixpkgs.packages.reflex-dom;  # every field, defaults filled
#     generated = true;
#     compose = pkgs.haskell.lib.compose;
#   })
#   => drv with that entry's patches, ghcOptions, Setup flags and
#      mkDerivation arguments applied, in that order
{ lib }:

{ name, tweaks, generated, compose }:

let setArg = attr: value: compose.overrideCabal (drv: { ${attr} = value; });

    appendArg = attr: values: compose.overrideCabal (drv: { ${attr} = drv.${attr} or [] ++ values; });

    toggleFlag = f: enabled:
      (if enabled
       then compose.enableCabalFlag
       else compose.disableCabalFlag) f;

    # Common `packages` fields that set one argument each of the Haskell
    # mkDerivation, mapped to the name the builder knows it by, which is not
    # always the option's own.
    packagesFieldArgs = (import ../package-fields.nix { inherit lib; }).args;

    patchSteps = tweaks:
      lib.optional (tweaks.patches != []) (compose.appendPatches tweaks.patches);

    # cabal2nix already applied the flags of a generated package.
    flagSteps = tweaks:
      lib.optionals (tweaks.flags != {} && !generated)
        (lib.mapAttrsToList toggleFlag tweaks.flags);

    ghcOptionSteps = tweaks:
      map (f: compose.appendConfigureFlag "--ghc-option=${f}") tweaks.ghcOptions;

    configureSteps = tweaks:
      lib.optional (tweaks.configureFlags != []) (compose.appendConfigureFlags tweaks.configureFlags);

    setupSteps = tweaks:
      lib.optional (tweaks.setupBuildFlags != []) (appendArg "buildFlags" tweaks.setupBuildFlags)
      ++ lib.optional (tweaks.setupHaddockFlags != []) (appendArg "haddockFlags" tweaks.setupHaddockFlags);

    fieldSteps = tweaks:
      lib.concatLists (lib.mapAttrsToList
        (field: attr: lib.optional (tweaks.${field} != null) (setArg attr tweaks.${field}))
        packagesFieldArgs);

    profilingStep = tweaks:
      lib.optional (tweaks.enableProfiling != null)
        (compose.overrideCabal (drv: {
          enableLibraryProfiling = tweaks.enableProfiling;
          enableExecutableProfiling = tweaks.enableProfiling;
        }));

    previousIntermediatesStep = tweaks:
      lib.optional (tweaks.previousIntermediates != null)
        (setArg "previousIntermediates" tweaks.previousIntermediates);

    srcStep = tweaks:
      lib.optional (tweaks.src != null) (compose.overrideSrc { inherit (tweaks) src; });

in patchSteps tweaks
   ++ flagSteps tweaks
   ++ ghcOptionSteps tweaks
   ++ configureSteps tweaks
   ++ setupSteps tweaks
   ++ fieldSteps tweaks
   ++ profilingStep tweaks
   ++ previousIntermediatesStep tweaks
   ++ srcStep tweaks
