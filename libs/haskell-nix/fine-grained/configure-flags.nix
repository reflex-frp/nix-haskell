# The configure flags of a package's plan under the haskell.nix driver.
# Cabal computes each module's ghc flags from these, so they must agree
# with the flags of the component's own build. `component` is the merged
# config of the package's library component.
#
# Example:
#
#   import ./configure-flags.nix { inherit lib; } {
#     name = "frontend";
#     component = config.packages.<id>.components.library;
#     ghc = config.ghc.package;
#     inherit pkgs;
#   }
#   => "lib:frontend --disable-executable-stripping
#       --disable-library-stripping --disable-library-profiling
#       --disable-profiling --enable-static --enable-shared
#       --disable-executable-dynamic --disable-coverage
#       --enable-library-for-ghci --enable-split-sections"
{ lib }:

{ name, component, ghc, pkgs }:

let platform = pkgs.stdenv.hostPlatform;

    prefix = import ../../message-prefix.nix { driver = "haskell.nix"; };

    feature = enabled: flag: "--${if enabled then "enable" else "disable"}-${flag}";

    ghcOption = option: "--ghc-option=${option}";

    profiling = component.enableProfiling || component.enableLibraryProfiling;

    target = [ "lib:${name}" ];

    stripping = lib.optionals component.dontStrip [
      "--disable-executable-stripping"
      "--disable-library-stripping"
    ];

    ways = [
      (feature component.enableLibraryProfiling "library-profiling")
      (feature component.enableProfiling "profiling")
      (feature component.enableStatic "static")
      (feature ((ghc.enableShared or false) && component.enableShared) "shared")
      (feature (component.enableExecutableDynamic && !platform.isMusl) "executable-dynamic")
      (feature component.doCoverage "coverage")
      (feature component.enableLibraryForGhci "library-for-ghci")
    ];

    detail = lib.optional (profiling && component.profilingDetail != null)
      "--profiling-detail=${component.profilingDetail}";

    sections = lib.optional platform.isLinux
      (feature component.enableDeadCodeElimination "split-sections");

    # The settings of ghc 9.8 and later carry no ld command, and the plan's
    # PATH carries no linker for Cabal to probe, so the linker is stated.
    linker = lib.optional (lib.versionAtLeast ghc.version "9.8")
      "--with-ld=${pkgs.stdenv.cc.bintools}/bin/${pkgs.stdenv.cc.bintools.targetPrefix}ld";

    stanzaOptions = map ghcOption component.ghcOptions;

    flags = lib.concatStringsSep " "
      (target ++ stripping ++ ways ++ detail ++ sections ++ linker
       ++ component.configureFlags
       ++ (ghc.extraConfigureFlags or [])
       ++ stanzaOptions);

    # The shim stops Cabal at its first `--make`, so the modules hold one
    # way. Cabal compiles the profiling way after that one.
    profilingCost = prefix ("fine-grained builds of `${name}` plan one build"
      + " way, so its profiling libraries compile every module a second time."
      + " Set `packages.${name}.enableLibraryProfiling` and"
      + " `packages.${name}.enableProfiling` to false.");

    costs = lib.optional profiling profilingCost;

in lib.foldl' (value: cost: lib.warn cost value) flags costs
