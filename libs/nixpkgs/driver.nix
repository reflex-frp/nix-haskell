# The nixpkgs driver core: builds the project from a nixpkgs Haskell package
# set. Parameterized on `pkgs` and `haskellPackages` so cross instantiations
# are one re-application with `pkgs.pkgsCross.<platform>`.
#
# Project interpretation reuses haskell.nix wherever it has something:
# cabal-project-parser for source-repository-package stanzas, host-map for
# cabal's platform names, and (with `options.use-plan`) the cabal plan of
# the haskell.nix driver for the definitive local package set.
#
# Every argument is a resolved value:
# - `common`: the common option values
# - `options`: the driver's own knobs
# - `haskell-nix-src`: the haskell.nix checkout
# - `haskell-nix`: the haskell.nix mirror values, read only under
#   `options.use-plan`
# - `cross-wrappers`: the wrapper-script function
#
# Example:
#
#   import ./driver.nix {
#     inherit pkgs haskellPackages lib common options
#       haskell-nix-src haskell-nix cross-wrappers;
#   }
#   => { packages.hello = <derivation>;
#        haskellPackages = <the extended package set>;
#        hsPkgs = <alias of haskellPackages>;
#        shell = <shellFor derivation>;
#        projectCross.<platform> = <the same shape, built with pkgsCross>;
#        ghcWithPackages = <function>;
#        pkgs = <the nixpkgs used>;
#      }
{ pkgs
, haskellPackages
, lib
, platform ? null
, common
, options
, haskell-nix-src
, haskell-nix
, cross-wrappers
}:

let compose = pkgs.haskell.lib.compose;

    # What the project asked for, with a cross platform's own customization
    # over the top. The platform's flags have to sit here rather than on a
    # built package. cabal2nix is told these flags, and a flag it does not
    # know about leaves the other platform's dependencies in place.
    packages =
      if platform == null
      then lib.seq unknownPlatforms common.packages
      else lib.recursiveUpdate common.packages (common.platforms.${platform}.packages or {});

    # Checked once, from the project this driver was asked for, since a name
    # that denotes no platform would otherwise simply never be looked up.
    prefix = import ../message-prefix.nix { driver = "nixpkgs"; };

    unknownPlatforms =
      let unknown = lib.subtractLists (builtins.attrNames pkgs.pkgsCross)
            (builtins.attrNames common.platforms);
      in if unknown == []
         then null
         else throw (prefix ("`platforms` names no such"
           + " platform: ${lib.concatStringsSep ", " unknown}"));

    # The `compiler` option resolved per platform.
    resolveCompiler = (import ../compiler { inherit lib; } {
      compiler = common.compiler;
      system = common.system;
      driver = "nixpkgs";
    }).resolve;

    # The package set a cross platform is built from:
    # - its own, when the compiler there brings a toolchain that has to
    #   become the whole set's
    # - else the one nixpkgs assembles for the platform
    crossPkgs = platform: common.pkgsCross.${platform} or pkgs.pkgsCross.${platform};

    hostMap = import (haskell-nix-src + "/lib/host-map.nix") pkgs.stdenv;
    project-file = import ./project-file.nix { inherit pkgs haskell-nix-src; };
    conditionHolds = condition: options.evaluate-condition { inherit condition hostMap; };
    decodeSrp = import ../source-repository-package.nix;
    haskellDependencies = import ./haskell-dependencies.nix { inherit lib; };
    haskellDependencyClosure = import ./haskell-dependency-closure.nix { inherit lib; };

    # ------------------------------------------------------------------------
    # Local packages: { <package-name> = { src; external; }; }
    # ------------------------------------------------------------------------

    # cabal's own reading of the project, taken from the haskell.nix driver's
    # plan. Packages rooted outside the project source (fetched
    # source-repository-packages) are marked external.
    planPackages =
      let proj = haskell-nix.project;
          projectSrc = toString haskell-nix.stages.src;
          locals = haskell-nix.lib.selectLocalPackages proj.hsPkgs;

          # `selectLocalPackages` keys by unit id and gives a package one entry
          # per component, so a project of one package arrives as
          # `reflex-todomvc-0.1.0.0-inplace` beside
          # `reflex-todomvc-0.1.0.0-inplace-reflex-todomvc`. Everything reading
          # this names a package, so the entries are keyed by the name each
          # carries and the components of one package collapse together.
          #
          # The source is still looked up under the unit id: the package set
          # answers to both, but only the unit id's entry carries a `src`.
          # A package under a subdirectory arrives as that directory rather
          # than as the project root: nixpkgs' `cleanSourceWith`, which
          # cabal2nix re-wraps a source in, carries `origSrc` but not
          # `origSubDir`, and would hand cabal2nix the root.
          entry = key: pkg:
            let src = proj.pkg-set.config.packages.${key}.src;
            in lib.nameValuePair pkg.identifier.name
                 { src = src.outPath or src;
                   external = toString (src.origSrc or src) != projectSrc;
                 };

      in lib.listToAttrs (lib.mapAttrsToList entry locals);

    # Discovered packages enter the set as { src; external; }. A package
    # the project source carries is never external.
    local = lib.mapAttrs (_: p: { inherit (p) src; external = false; });

    discovered =
      if options.packages != null
      then local (options.discover-packages { src = common.src-cleaned; explicit = options.packages; })
      else if options.use-plan
      then planPackages
      else local (options.discover-packages { src = common.src-cleaned; explicit = null; });

    # ------------------------------------------------------------------------
    # source-repository-packages: { <package-name> = <src dir>; }
    # ------------------------------------------------------------------------

    # Skipped under use-plan: the plan already contains them.

    packageAt = project-file.packageAt;

    srpOptionPackages =
      let entry = attrName: spec:
            let inherit (decodeSrp spec) src condition subdirs;
                subdirsOrRoot =
                  if subdirs == []
                  then [ "." ]
                  else subdirs;
            in lib.optionals (condition == null || conditionHolds condition)
                 (map (packageAt src "source-repository-packages.${attrName}") subdirsOrRoot);
      in builtins.listToAttrs
           (lib.concatLists (lib.mapAttrsToList entry common.source-repository-packages));

    # The project text the stanzas are read from: the project file (or the
    # cabalProject option, which replaces it), cabal.project.local and the
    # extraCabalProject lines.
    projectText = options.project-text {
      projectFile = project-file.projectFileText common.cabalProjectFileName common.src-cleaned;
      inherit (common) cabalProject cabalProjectLocal extraCabalProject;
    };

    # Stanzas written in the project's own cabal.project.
    srpStanzaPackages =
      let entry = r:
            let src = options.fetch-stanza-source { stanza = r; inputMap = common.inputMap; inherit pkgs; };
            in map (packageAt src "source-repository-package ${r.url}") r.subdirs;
      in builtins.listToAttrs
           (lib.concatLists (map entry (project-file.sourceRepoStanzas common.sha256map projectText)));

    srpPackages =
      lib.optionalAttrs (!options.use-plan) (srpOptionPackages // srpStanzaPackages);

    # ------------------------------------------------------------------------
    # The package set: one fixpoint extension over the base set
    # ------------------------------------------------------------------------

    # Every package source reaches the set the same way: cabal2nix over a
    # { src; external; } entry, keyed by package name.
    cabal2nixOverlay = entries: self: _:
      lib.mapAttrs
        (name: e: self.callCabal2nixWithOptions name e.src
          (options.cabal2nix-options {
            inherit name;
            external = e.external;
            tweaks = packages.${name} or {};
            extra-package-defaults = options.extra-package-defaults;
          }) {})
        entries;

    localPackagesOverlay = cabal2nixOverlay discovered;

    srpOverlay = cabal2nixOverlay
      (lib.mapAttrs (_: src: { inherit src; external = true; }) srpPackages);

    hackageOverlay = cabal2nixOverlay
      (builtins.listToAttrs
        (map (o: lib.nameValuePair o.name { inherit (o) src; external = true; })
          common.hackage-overlays));

    # Packages rooted outside the project source get pragmatic defaults.
    # Without a solver, their version bounds routinely need loosening.
    externalNames =
      lib.attrNames (lib.filterAttrs (_: p: p.external) discovered)
      ++ lib.attrNames srpPackages
      ++ map (o: o.name) common.hackage-overlays;

    extraDefaultsOverlay = _: super:
      let d = options.extra-package-defaults;
      in lib.genAttrs externalNames (name: lib.pipe super.${name} (
           lib.optional d.jailbreak compose.doJailbreak
           ++ lib.optional (!d.check) compose.dontCheck
           ++ lib.optional (!d.haddock) compose.dontHaddock));

    generatedNames = lib.attrNames discovered ++ lib.attrNames srpPackages;

    # Overlay attribute names must never depend on package values, or the
    # fixpoint recurses. Presence (super ? name) decides the names, and
    # nulls pass through in the values.
    packageTweaksOverlay = _: super:
      let tweak = name: tweaks:
            if super.${name} == null
            then null
            else lib.pipe super.${name} (options.package-steps {
              inherit name tweaks compose;
              generated = lib.elem name generatedNames;
            });

          # Tweaks for packages absent from the set are silently ignored.
          present = lib.filterAttrs (name: _: super ? ${name}) packages;

      in lib.mapAttrs tweak present;

    # Project-wide ghcOptions apply to the project's own packages. Applying
    # them to the whole set would invalidate the binary cache for the entire
    # dependency closure.
    ghcOptionsOverlay = _: super:
      lib.genAttrs (lib.attrNames discovered)
        (name: lib.pipe super.${name}
          (map (f: compose.appendConfigureFlag "--ghc-option=${f}") common.ghcOptions));

    # How a package is configured rather than which package it is, so it goes on
    # the set's `mkDerivation` rather than on names.
    exactConfigurationOverlay = _: super: {
      mkDerivation = args: super.mkDerivation (args // {
        preConfigure = (args.preConfigure or "") + options.exact-configuration-hook {
          ghc = "${haskellPackages.ghc.targetPrefix}ghc";
        };
      });
    };

    packageArgumentsOverlay = _: super:
      let override = name: args:
            if super.${name} == null
            then null
            else compose.overrideCabal (_: args) super.${name};
      in lib.mapAttrs override
           (lib.filterAttrs (name: _: super ? ${name}) options.package-arguments);

    # ------------------------------------------------------------------------
    # Fine-grained builds
    # ------------------------------------------------------------------------

    fineGrained = common.fine-grained;

    fineGrainedShim = fineGrained.ghc-shim {
      inherit pkgs;
      ghc = haskellPackages.ghc;
    };

    # Native packages only. A plan builds Setup with the compiler it
    # configures with, and a cross set's Setup cannot run on the builder.
    fineGrainedNames =
      if platform != null || !fineGrained.enable
      then []
      else if fineGrained.packages != null
      then fineGrained.packages
      else lib.attrNames (lib.filterAttrs (_: p: !p.external) discovered);

    # This overlay comes last, so that each plan reads the package as it
    # builds. The names come from the selection, never from a package value.
    fineGrainedOverlay = _: super:
      let plan = name:
            let package = super.${name};
                tweaks = packages.${name} or {};

                flags = fineGrained.configure-flags {
                  inherit name tweaks pkgs;
                  ghc = haskellPackages.ghc;
                  ghc-options = common.ghcOptions;
                };

                intermediates = fineGrained.intermediates {
                  inherit name package pkgs;
                  ghc = haskellPackages.ghc;
                  dependencies = haskellDependencyClosure package;
                  shim = fineGrainedShim;
                  tool = fineGrained.tool;
                  configure-flags = flags;
                };

            in if !(super ? ${name}) || package == null
               then throw (prefix ("`fine-grained.packages` names a package the"
                      + " set carries no build for: ${name}"))
               else compose.overrideCabal (_: {
                      previousIntermediates = builtins.outputOf intermediates.outPath "out";
                    }) package;

      in lib.genAttrs fineGrainedNames plan;

    projectOverlays =
      lib.optional options.exact-configuration exactConfigurationOverlay
      ++ [ localPackagesOverlay srpOverlay hackageOverlay extraDefaultsOverlay packageTweaksOverlay ]
      ++ lib.optional (common.ghcOptions != []) ghcOptionsOverlay
      ++ lib.optional (options.package-arguments != {}) packageArgumentsOverlay
      ++ options.overrides
      ++ lib.optional (fineGrainedNames != []) fineGrainedOverlay;

    hp = haskellPackages.extend (lib.composeManyExtensions
      (options.project-overlays { overlays = projectOverlays; }));

    # ------------------------------------------------------------------------
    # Shell
    # ------------------------------------------------------------------------

    # What `shell.packages` selects from: the project's packages plus
    # source-repository-packages, tagged the way selection functions expect.
    # Tagging with // preserves outPath, which shellFor's local-package
    # detection compares. The full package set is never offered. It contains
    # null (boot) and throwing (removed) attributes.
    selectionSet =
      lib.genAttrs generatedNames
        (name: hp.${name} // { isLocal = true; identifier = { inherit name; }; });

    selection = import ../shell-packages-selection.nix {
      packages = common.shell.packages;
      inherit (common) source-repository-packages;
    };

    resolveTool = name: request: options.resolve-shell-tool {
      inherit name request pkgs;
      tool-packages = options.tool-packages;
      haskellPackages = hp;
    };

    # The wrapped cross compiler carries the dependencies of the shell
    # selection in its package database, like shellFor's environment does
    # for the native compiler. Without a hackage index in the shell, cabal
    # can only resolve against installed packages.
    #
    # The wrapper comes from cross-ghc-env.nix rather than from the set's
    # own `ghcWithPackages`, which aims the compiler at a library directory
    # it builds from the version and so cannot wrap a relocatable bindist.
    crossGhcEnv = platform:
      let chp = projectCross.${platform}.haskellPackages;
          selected = map (p: chp.${p.identifier.name}) (selection selectionSet);
          notSelected = d: lib.all (p: (d.outPath or null) != p.outPath) selected;
      in options.cross-ghc-env {
           ghc = chp.ghc;
           packages = lib.filter notSelected (lib.concatMap haskellDependencies selected);
           inherit pkgs;
         };

    crossWrappers =
      let probe = (import ../cross/platform.nix { inherit lib; }).probe pkgs;
      in lib.concatMap (platform: cross-wrappers { ghc = crossGhcEnv platform; inherit pkgs; })
           (common.shell.crossPlatforms probe);

    shellArgs = {
      packages = _: selection selectionSet;
      withHoogle = common.shell.withHoogle;
      nativeBuildInputs =
        lib.mapAttrsToList resolveTool common.shell.tools
        ++ common.shell.nativeBuildInputs
        ++ crossWrappers;
      buildInputs = common.shell.buildInputs;
      shellHook = common.shell.shellHook;
    } // lib.optionalAttrs (common.name != null) { name = "${common.name}-shell"; }
      // options.shellFor-args;

    shell = hp.shellFor (options.shell-arguments { args = shellArgs; });

    # ------------------------------------------------------------------------
    # Cross
    # ------------------------------------------------------------------------

    projectCross = lib.genAttrs (builtins.attrNames pkgs.pkgsCross) (crossPlatform:
      let platformPkgs = crossPkgs crossPlatform;
      in import ./driver.nix {
        pkgs = platformPkgs;
        haskellPackages = options.haskell-packages-for {
          pkgs = platformPkgs;
          compiler = resolveCompiler crossPlatform;
        };
        inherit lib common options haskell-nix-src haskell-nix cross-wrappers;
        platform = crossPlatform;
      });

in {
  inherit pkgs shell projectCross;
  haskellPackages = hp;
  # Rough symmetry with the haskell.nix project. There is no per-component
  # tree: haskell.nix's hsPkgs.<name>.components.exes.<exe> corresponds to
  # packages.<name> here (with the executable at $out/bin/<exe>).
  hsPkgs = hp;
  packages = lib.genAttrs (lib.attrNames discovered) (name: hp.${name});
  ghcWithPackages = hp.ghcWithPackages;
}
