# Interprets the common `compiler` option. Each platform resolves to the
# names a build needs, and to a compiler derivation carrying the attributes
# the drivers read off it.
#
# A field of an entry resolves in this order:
# 1. The value the entry states.
# 2. Whatever the compiler package already carries, so a driver's own
#    compilers need no fields at all.
# 3. A neutral value.
#
# The entry carries three names:
#
#   name       the project-wide key: the compiler the driver looks up by name,
#              and the package set whose compiler a package replaces
#   stockName  the driver's own compiler of the same major.minor.patch,
#              derived from the version alone. The builds that cannot use the
#              package itself go here: the nixpkgs package set the project is
#              built against, haskell.nix's shell tools. Deriving it from the
#              version rather than from `name` keeps an overridden name from
#              sending those builds to a set that does not exist.
#   annotated  the package with the attributes spliced back on
#
# Example:
#
#   compilers = import ./compiler { inherit lib; } {
#     compiler = config.compiler;
#     system = "x86_64-linux";
#   };
#   => { native = <entry>; resolve = <key: entry>;
#        targetKey = <targetPlatform: key or null>;
#        anyToolchain = <bool>; anyExtraNonReinstallablePkgs = <bool>; }
#   compilers.native
#   => { name = "ghc912"; stockName = "ghc912"; package = null; annotated = null; ... }
#   compilers.resolve "wasi32"
#   => { name = "ghc912"; stockName = "ghc9124"; annotated = <bindist // { ... }>;
#        toolchainFlags = [ "--with-gcc=/nix/store/...-wasi-sdk/bin/wasm32-wasi-clang" ... ]; }
#   compilers.targetKey <elaborated wasi32>    => "wasi32"
#   compilers.targetKey <elaborated x86_64>    => "x86_64-linux"
#   compilers.targetKey <elaborated aarch64>   => null
{ lib }:

{ compiler, system, driver ? null }:

with lib;

with (import ../common { inherit lib; });

let prefix = message-prefix { inherit driver; };

    crossPlatform = import ../cross/platform.nix { inherit lib; };

    platforms = compiler.platforms;

    # ------------------------------------------------------------------------
    # One entry
    # ------------------------------------------------------------------------

    entry = where: spec:
      let package = spec.package;

          # A field resolves to the entry's value, then to the package's
          # attribute, then to the given fallback.
          fromSpecOr = specValue: attr: fallback:
            if specValue != null
            then specValue
            else package.${attr} or fallback;

          version =
            if spec.version != null
            then spec.version
            else if package == null
            then null
            else
              let parsed = getVersion package;
              in if parsed != ""
                 then parsed
                 else throw (prefix ("cannot derive a version for"
                   + " `compiler${where}` from ${package.name or "<compiler package>"};"
                   + " set `compiler${where}.version`"));

          name =
            if spec.name != null
            then spec.name
            else if version != null
            then "ghc" + replaceStrings [ "." ] [ "" ] version
            else throw (prefix ("`compiler${where}` has no name and nothing"
              + " to derive one from; set `compiler${where}.name`"));

          stockName =
            if version == null
            then name
            else "ghc" + concatStrings (take 3 (splitVersion version));

          targetPrefix = fromSpecOr spec.targetPrefix "targetPrefix" "";

          enableShared = fromSpecOr spec.enableShared "enableShared" true;

          libDir = spec.haskell-nix.libDir;

          versionedCompilerName =
            if version == null
            then null
            else "ghc-${version}";

          haskellCompilerName =
            fromSpecOr spec.nixpkgs.haskellCompilerName "haskellCompilerName" versionedCompilerName;

          toolchain = spec.toolchain;

          hasToolchain = toolchain.package != null;

          # The cabal flags pointing a build at the compiler's own C tools.
          # One list for both drivers, so a build gets the same toolchain
          # whichever one runs it. cabal takes a repeated flag from its last
          # occurrence, so these override what a driver passes from the
          # surrounding package set.
          toolchainFlags =
            let flag = tool:
                  optional (toolchain.${tool.name} != null)
                    "--with-${tool.flag}=${toolchain.package}/bin/${toolchain.${tool.name}}";

                extraFlags = mapAttrsToList
                  (key: bin: "--with-${key}=${toolchain.package}/bin/${bin}")
                  (toolchain.extra or {});

            in optionals hasToolchain
                 (concatMap flag (import ./toolchain-tools.nix) ++ extraFlags);

      in {
        inherit name stockName version targetPrefix enableShared package;
        inherit toolchain toolchainFlags hasToolchain;
        inherit (spec.haskell-nix) extraNonReinstallablePkgs;
        inherit (spec.nixpkgs) enableExternalInterpreter;

        annotated =
          if package == null
          then null
          else package
            // { inherit version targetPrefix enableShared; }
            // optionalAttrs (libDir != null) { inherit libDir; }
            // optionalAttrs (haskellCompilerName != null) { inherit haskellCompilerName; };
      };

    # ------------------------------------------------------------------------
    # Every entry the project declared
    # ------------------------------------------------------------------------

    nativeEntry = entry "" (removeAttrs compiler [ "platforms" ]);

    platformEntries = mapAttrs (key: entry ".platforms.${key}") platforms;

    allEntries = [ nativeEntry ] ++ attrValues platformEntries;

in {

  # --------------------------------------------------------------------------
  # What a driver asks
  # --------------------------------------------------------------------------

  native = nativeEntry;

  # The per-platform entries, keyed as the `platforms` table declares them.
  platforms = platformEntries;

  # A platform's own entry when it has one, else the compiler above the table.
  # An entry is additive, so an ordinary cross target keeps working with only
  # one compiler declared.
  resolve = key:
    if key == null || ! (platformEntries ? ${key})
    then nativeEntry
    else platformEntries.${key};

  # Whether any entry asks for machinery a driver only needs when a compiler
  # is described this way:
  # - a toolchain to point builds at
  # - boot packages to take from the compiler rather than build
  # - a compiler package, whose database names more boot packages
  anyToolchain = any (e: e.hasToolchain) allEntries;

  anyExtraNonReinstallablePkgs = any (e: e.extraNonReinstallablePkgs != []) allEntries;

  anyPackage = any (e: e.package != null) allEntries;

  # The `platforms` key for a target platform, or null when no entry matches
  # and the compiler above the table applies.
  targetKey = targetPlatform:
    let crossKeys = filter (key: key != system) (attrNames platforms);
    in if targetPlatform.system == system
       then system
       else crossPlatform.keyFor crossKeys targetPlatform;

}
