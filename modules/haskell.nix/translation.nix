# How every common option maps onto haskell.nix: the `translation` table.
# The `set` payloads populate `haskell-nix.options`. The `via` strings are
# the table's documentation. The totality check compares the keys against
# the common options in both directions.
{ lib, pkgs, config, cfg, compiler, compilers, srpStanzaLines, withToolCompiler }:

with lib;
with (import ../../libs/prelude { inherit lib; });

let translations = import ../../libs/driver/translation.nix { inherit lib; };

    packageFields = import ../../libs/package-fields.nix { inherit lib; };

    # ------------------------------------------------------------------------
    # Compiler selection
    # ------------------------------------------------------------------------

    selectionNeeded = cfg.compiler.platforms != {} || compiler.package != null;

    prefix = import ../../libs/message-prefix.nix { driver = "haskell.nix"; };

    missingCompiler = key:
      throw (prefix "haskell-nix.compiler has no \"${key}\"");

    foreignPlatformName = target:
      throw (prefix ("the compiler named \"${target.name}\""
        + " differs from the project-wide \"${compiler.name}\"; this driver's cross projects"
        + " share one name, so a platform of its own needs a `package`"));

    # `cachedDeps` carries the boot packages' exact-configuration flags.
    # haskell.nix's own compilers have it. For a compiler that does not, the
    # fallback interpolates the compiler itself instead of the deps and
    # leaves every boot package unresolved, so it is attached here.
    compilerFor = target: key: p:
      if target.annotated != null
      then cfg.lib.makeCompilerDeps target.annotated
      else if target.name == compiler.name
      then p.haskell-nix.compiler.${key} or (missingCompiler key)
      else foreignPlatformName target;

    selectCompiler = p:
      let target = compilers.resolve (compilers.targetKey p.stdenv.targetPlatform);
          key = p.haskell-nix.resolve-compiler-name compiler.name;
      in { ${key} = compilerFor target key p; };

    # ------------------------------------------------------------------------
    # Shell inputs
    # ------------------------------------------------------------------------

    # Wrapper scripts for the cross platforms selected by
    # `shell.crossPlatforms`, built from this driver's own cross projects.
    crossWrappers =
      concatMap (p: config.cross-wrappers { ghc = p.shell.ghc; inherit pkgs; })
        (cfg.shell.crossPlatforms cfg.project.projectCross);

    # ------------------------------------------------------------------------
    # Per-package modules
    # ------------------------------------------------------------------------

    # One haskell.nix module per field of the common `packages` option. The
    # inner `config` is haskell.nix's own, so `? name` skips packages absent
    # from the project.
    packagesField = field: translate:
      let relevant = filterAttrs (_: tweaks: is-set tweaks.${field}) cfg.packages;
      in mkIf (relevant != {}) {
        modules = [
          ({ config, ... }: {
            packages = mapAttrs (_: translate)
              (filterAttrs (name: _: config.packages ? ${name}) relevant);
          })
        ];
      };

    # Per-package fields translated verbatim into a haskell.nix module. The
    # names are haskell.nix's own. Only `src` needs special handling and has
    # an explicit entry in the table.
    packagesFieldNames = packageFields.names;

    packagesTranslation = listToAttrs (map (field: nameValuePair "packages.*.${field}" {
      set = packagesField field (t: { ${field} = t.${field}; });
      via = "a `packages.<name>.${field}` module";
    }) packagesFieldNames);

    # Not a verbatim field: haskell.nix has no such option. The library
    # component's `preBuild` seeds `dist/build` before `Setup build`.
    previousIntermediates =
      let relevant = filterAttrs (_: tweaks: tweaks.previousIntermediates != null) cfg.packages;

          restore-intermediates = import ../../libs/haskell-nix/restore-intermediates.nix { inherit lib; };

      in mkIf (relevant != {}) {
        modules = [
          ({ config, ... }: {
            packages = mapAttrs (name: tweaks: {
              components.library.preBuild = restore-intermediates {
                ghc = config.ghc.package;
                pname = name;
                user-hook = config.packages.${name}.preBuild;
                intermediates = tweaks.previousIntermediates;
              };
            }) (filterAttrs (name: _: config.packages ? ${name}) relevant);
          })
        ];
      };

    # The executables a project named, gathered from the project-wide entries
    # and from every target's, so one named for a single target is installed
    # too. Naming an executable that has no `.jsexe` costs nothing: the module
    # looks for the directory before copying it.
    namedExes =
      let exesIn = packages:
            mapAttrs (_: tweaks: attrNames tweaks.components.exes)
              (filterAttrs (_: tweaks: tweaks.components.exes != {}) packages);
          trees = [ cfg.packages ] ++ map (target: target.packages) (attrValues cfg.platforms);
      in zipAttrsWith (_: named: unique (concatLists named)) (map exesIn trees);

in {

  # --------------------------------------------------------------------------
  # The table
  # --------------------------------------------------------------------------

  translation = translations.declare {
    driver = "haskell.nix";
    extra = "The `set` payloads populate `haskell-nix.options`. ";
    default = {

      system.via = "the haskell.nix checkout is imported for `system`";

      name.set = mkIf (cfg.name != null) { name = cfg.name; };
      name.via = "project `name`";

      src.set = { src = mkForce cfg.stages.src; };
      src.via = "the `stages.src` derivation built from `src-cleaned`";

      "compiler.name".set =
        { compiler-nix-name = compiler.name; }
        // optionalAttrs selectionNeeded {
          # Keyed by the name haskell.nix resolves compiler-nix-name to,
          # so the (compilerSelection pkgs).${name} lookups always hit
          # this selection. Cross projects share the one name, so
          # per-platform entries dispatch on the selection's target
          # platform. An entry that only renames the compiler has
          # nothing to dispatch to.
          compilerSelection = selectCompiler;
        };
      "compiler.name".via = "project `compiler-nix-name` (the compiler above `platforms`); packages are pinned under it through `compilerSelection`, dispatched on the target platform";

      "compiler.toolchain".set = mkIf compilers.anyToolchain {
        modules = [
          (import ../../libs/haskell-nix/compiler-toolchain.nix { inherit lib compilers; })
        ];
      };
      "compiler.toolchain".via = "a module giving every package the compiler's own configure flags, on the platforms whose entry carries a toolchain";

      "compiler.package".via = "the compiler `compilerSelection` returns for its platform, carrying haskell.nix's `cachedDeps`";
      "compiler.version".via = "spliced onto the compiler as `ghc.version`; the compiler the shell tools are built with is the driver's own of that version";
      "compiler.enableShared".via = "spliced onto the compiler as `ghc.enableShared`, which decides every component's `shared:`";
      "compiler.haskell-nix".set = mkIf compilers.anyExtraNonReinstallablePkgs {
        modules = [
          (import ../../libs/haskell-nix/non-reinstallable.nix {
            inherit lib compilers;
            haskell-nix-src = config.inputs."haskell-nix";
          })
        ];
      };
      "compiler.haskell-nix".via = "`libDir` is spliced onto the compiler, where the package database and `settings` are looked for; `extraNonReinstallablePkgs` is appended to `nonReinstallablePkgs` by a module, on the platforms whose entry names any";
      "compiler.nixpkgs".via = "read by the nixpkgs driver only";
      "compiler.platforms".via = "resolved per target platform by `compilerSelection` and by the toolchain module";

      cabalProject.set = mkIf (cfg.cabalProject != null) {
        # the project file (carrying the stanzas `stages.src` appended)
        # is ignored when cabalProject is set, so they move into it
        cabalProject = concatStringsSep "\n" (
          [ cfg.cabalProject ]
          ++ srpStanzaLines
          ++ cfg.extraCabalProject
        );
      };
      cabalProject.via = "project `cabalProject`, with the generated source-repository-package stanzas and `extraCabalProject` appended";

      cabalProjectLocal.set = mkIf (cfg.cabalProjectLocal != null) {
        cabalProjectLocal = cfg.cabalProjectLocal;
      };
      cabalProjectLocal.via = "project `cabalProjectLocal`";

      cabalProjectFileName.set = { cabalProjectFileName = cfg.cabalProjectFileName; };
      cabalProjectFileName.via = "project `cabalProjectFileName`";

      extraCabalProject.via = "appended to cabal.project by `stages.src`, or to `cabalProject` when that is set";

      inputMap.set = mkIf (cfg.inputMap != {}) { inputMap = cfg.inputMap; };
      inputMap.via = "project `inputMap`, merged with the generated source-repository-package entries";

      sha256map.set = mkIf (cfg.sha256map != null) { sha256map = cfg.sha256map; };
      sha256map.via = "project `sha256map`";

      source-repository-packages.set = { inputMap = cfg.stages.source-repository-packages.inputMap; };
      source-repository-packages.via = "`source-repository-package` stanzas appended by `stages.src`, with `inputMap` pinning their sources";

      hackage-overlays.set = mkIf (cfg.hackage-overlays != []) {
        extra-hackage-tarballs = cfg.stages.hackage.extra-hackage-tarballs;
        extra-hackages = cfg.stages.hackage.extra-hackages;
        modules = cfg.stages.hackage.package-overlays;
      };
      hackage-overlays.via = "`stages.hackage`'s generated hackage index, package sets and src overrides";

      ghcOptions.set = mkIf (cfg.ghcOptions != []) {
        modules = [ { ghcOptions = cfg.ghcOptions; } ];
      };
      ghcOptions.via = "a project-wide `ghcOptions` module";

      "fine-grained.enable".via = "the project is re-evaluated in the `project` apply, with a module restoring each selected library from its plan; the plans read the project evaluated without it";
      "fine-grained.packages".via = "the selection the restore module covers; `null` is every local library of the cabal plan";
      "fine-grained.sandstone".via = "the checkout `tool` and `nix` default to";
      "fine-grained.tool".via = "`cabal-dyn-drv`, which every plan hands over to";
      "fine-grained.nix".via = "consumed by no build; the Nix a user runs these builds with";
      "fine-grained.ghc-shim".via = "applied to the project's ghc; the compiler a plan's configure records";
      "fine-grained.configure-flags".via = "each plan's configure flags, computed from the library component's own config";
      "fine-grained.intermediates".via = "each plan derivation, whose output the library's `preBuild` restores";

      "packages.*.src" = {
        set = packagesField "src" (t: { src = mkForce t.src; });
        via = "a `packages.<name>.src` module";
      };

      "packages.*.previousIntermediates" = {
        set = previousIntermediates;
        via = "a `preBuild` restore on the package's library component; a fine-grained plan replaces it for the packages it selects";
      };

      "platforms.*.packages".set = mkIf (cfg.platforms != {}) {
        modules = [
          (import ../../libs/haskell-nix/platform-packages.nix {
            inherit lib;
            platforms = cfg.platforms;
            fields = packagesFieldNames;
          })
        ];
      };
      "platforms.*.packages".via = "a `packages.<name>` module applied in the project whose target is that platform";

      "packages.*.components".set = mkIf (namedExes != {}) {
        modules = [
          (import ../../libs/haskell-nix/install-jsexe.nix {
            inherit lib;
            exes = namedExes;
          })
        ];
      };
      "packages.*.components".via = "an `<exe>.jsexe` install for every executable named, in the project whose target is javascript";

      "shell.packages".set = {
        shell.packages = import ../../libs/shell-packages-selection.nix {
          packages = cfg.shell.packages;
          inherit (cfg) source-repository-packages;
        };
      };
      "shell.packages".via = "`shell.packages`, defaulting to the project's local packages";

      "shell.tools".set = { shell.tools = mapAttrs (_: withToolCompiler) cfg.shell.tools; };
      "shell.tools".via = "`shell.tools`; with a package compiler, tools are pinned to the stock compiler matching its version";

      "shell.buildInputs".set = { shell.buildInputs = cfg.shell.buildInputs ++ crossWrappers; };
      "shell.buildInputs".via = "`shell.buildInputs`, with cross wrapper scripts appended";

      "shell.nativeBuildInputs".set = { shell.nativeBuildInputs = cfg.shell.nativeBuildInputs; };
      "shell.nativeBuildInputs".via = "`shell.nativeBuildInputs`";

      "shell.shellHook".via = "appended to the project shell with overrideAttrs, deferring its evaluation";
      "shell.withHoogle".via = "applied to the project shell with overrideAttrs, deferring its evaluation";

      "shell.crossPlatforms".set = { shell.crossPlatforms = cfg.shell.crossPlatforms; };
      "shell.crossPlatforms".via = "`shell.crossPlatforms` (haskell.nix cross projects are keyed by the same `pkgsCross` names)";

      cross-wrappers.via = "called with the shell ghc of every cross project `shell.crossPlatforms` selects; the scripts join the shell's inputs";

      inputs.via = "`inputs.haskell-nix` supplies the haskell.nix checkout the driver imports";

    } // packagesTranslation
      // translations.common-vias {
        namespace = "haskell-nix";
        src-consumer = "feeds `stages.src`";
      };
  };

}
