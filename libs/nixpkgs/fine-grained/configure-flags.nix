# The configure flags of a package's plan. Cabal computes each module's ghc
# flags from these, so they must agree with the flags of the package's own
# build. An unset `packages.<name>` field uses the nixpkgs default.
#
# Example:
#
#   import ./configure-flags.nix { inherit lib; } {
#     name = "frontend";
#     tweaks = {
#       enableLibraryProfiling = false;
#       doHaddock = false;
#       enableDeadCodeElimination = false;
#     };
#     ghc-options = [ "-Wall" ];
#     inherit ghc pkgs;
#   }
#   => "--disable-library-profiling --enable-shared --enable-static
#       --enable-library-vanilla --disable-library-for-ghci
#       --disable-split-sections --ghc-option=-Wall"
{ lib }:

{ name, tweaks, ghc-options, ghc, pkgs }:

let platform = pkgs.stdenv.hostPlatform;

    prefix = import ../../message-prefix.nix { driver = "nixpkgs"; };

    stated = field: fallback:
      if (tweaks.${field} or null) == null
      then fallback
      else tweaks.${field};

    feature = enabled: flag: "--${if enabled then "enable" else "disable"}-${flag}";

    ghcOption = option: "--ghc-option=${option}";

    profiling = stated "enableLibraryProfiling" (!platform.isGhcjs);

    haddockPhase = stated "doHaddock" true;

    # `-haddock` changes the interfaces that ghc writes. The plan states it
    # only when the package's own build states it.
    documentation = haddockPhase && lib.versionAtLeast ghc.version "9.0.1";

    shared = stated "enableShared"
      (!platform.isStatic && (ghc.enableShared or false) && !platform.useAndroidPrebuilt);

    static = stated "enableStatic"
      (!(platform.isWindows || platform.isWasm || platform.isGhcjs));

    ways = [
      (feature profiling "library-profiling")
      (feature shared "shared")
      (feature static "static")
      "--enable-library-vanilla"
      (feature (stated "enableLibraryForGhci" false) "library-for-ghci")
      (feature (stated "enableDeadCodeElimination" (!platform.isDarwin)) "split-sections")
    ];

    detail = lib.optional profiling
      "--profiling-detail=${stated "profilingDetail" "exported-functions"}";

    interfaces = lib.optional documentation (ghcOption "-haddock");

    # Nixpkgs asks ghc 9.12 and later for deterministic objects. The flag
    # reaches every module, and ghc reads it when it decides whether the
    # modules of a plan still stand.
    determinism = lib.optional (lib.versionAtLeast ghc.version "9.12")
      (ghcOption "-fobject-determinism");

    stanzaOptions = map ghcOption (ghc-options ++ (tweaks.ghcOptions or []));

    # Cabal hashes the flag assignment into the unit id, so a plan that
    # leaves a stated flag to its default computes another id, and ghc
    # turns every module down over the name alone.
    assignments = lib.mapAttrsToList
      (flag: enabled: "-f" + lib.optionalString (!enabled) "-" + flag)
      (tweaks.flags or {});

    flags = lib.concatStringsSep " "
      (assignments ++ ways ++ detail ++ interfaces ++ determinism ++ stanzaOptions
       ++ (tweaks.configureFlags or []));

    # The shim stops Cabal at its first `--make`, so the modules hold one
    # way. Cabal compiles the profiling way after that one.
    profilingCost = prefix ("fine-grained builds of `${name}` plan one build"
      + " way, so its profiling libraries compile every module a second time."
      + " Set `packages.${name}.enableLibraryProfiling` to false.");

    # Haddock reads sources rather than compiled modules, so no plan reaches
    # it.
    haddockCost = prefix ("fine-grained builds of `${name}` leave its"
      + " documentation alone, and that reads every module again."
      + " Set `packages.${name}.doHaddock` to false.");

    # What the package pays for on top of the modules a plan holds.
    costs =
      lib.optional profiling profilingCost
      ++ lib.optional haddockPhase haddockCost;

in lib.foldl' (value: cost: lib.warn cost value) flags costs
