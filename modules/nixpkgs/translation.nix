# How every common option maps onto nixpkgs: the `translation` table. This
# driver honors the common options in its own pipeline rather than by
# passing them on, so every entry is a `via` string saying where the option
# is honored. The totality check compares the keys against the common
# options in both directions.
{ lib }:

with lib;

let translations = import ../../libs/driver/translation.nix { inherit lib; };

    packageFields = import ../../libs/package-fields.nix { inherit lib; };

in {

  translation = translations.declare {
    driver = "nixpkgs";
    default = {

      system.via = "the package set is instantiated for `system`";

      name.via = "names the development shell";

      src.via = "local packages are discovered in `src-cleaned` and built with callCabal2nix";

      "compiler.name".via = "selects `pkgs.haskell.packages.<name>`; with a package, names the set whose `ghc` it replaces";
      "compiler.package".via = "replaces the `ghc` of the base package set";
      "compiler.version".via = "spliced onto the compiler as `ghc.version`; the package set the project is built against is the one of that major.minor.patch";
      "compiler.enableShared".via = "a cross package set is built non-static, with shared and not static libraries";
      "compiler.toolchain".via = "becomes a cross package set's own toolchain, a setup dependency of every package, and every package's configure flags";
      "compiler.haskell-nix".via = "read by the haskell.nix driver only";
      "compiler.nixpkgs".via = "`haskellCompilerName` is spliced onto the compiler, naming the package database directories of everything built and cabal2nix's `--compiler`; `enableExternalInterpreter` is passed to every package in a cross set";
      "compiler.platforms".via = "each entry gives `projectCross.<platform>` its own compiler, and with a toolchain its own package set (`nixpkgs.pkgsCross`)";

      "platforms.*.packages".via = "merged over `packages` for `projectCross.<platform>`, before cabal2nix is told a package's flags";
      "packages.*.components".via = "nothing to do: for a ghcjs target the generic builder already copies every `dist/build/*/*.jsexe` into `$out/bin`";

      cabalProject.via = "replaces the project file as the text whose source-repository-package stanzas are honored";
      cabalProjectLocal.via = "appended to the project text before stanza parsing";
      cabalProjectFileName.via = "the project file read for stanzas";
      extraCabalProject.via = "appended to the project text before stanza parsing";
      inputMap.via = "stanza urls (or url/rev) resolve through it before fetching";
      sha256map.via = "hashes for fetching stanza sources, like `--sha256` comments";

      source-repository-packages.via = "callCabal2nix on the resolved sources, one entry per `subdir`; `condition` is evaluated against the target platform (haskell.nix's host-map); stanzas in cabal.project are parsed by haskell.nix's parser and fetched";

      hackage-overlays.via = "callCabal2nix entries in the package set";

      ghcOptions.via = "`--ghc-option` configure flags on the project's packages";

      "fine-grained.enable".via = "selected native packages get a sandstone plan each, in the last overlay of the set, and their builds resume from it";
      "fine-grained.packages".via = "the selection that overlay covers; `null` is every discovered non-external package";
      "fine-grained.sandstone".via = "the checkout `tool` and `nix` default to";
      "fine-grained.tool".via = "`cabal-dyn-drv`, which every plan hands over to";
      "fine-grained.nix".via = "consumed by no build; the Nix a user runs these builds with";
      "fine-grained.run".via = "consumed by no build; `fine-grained.nix` wrapped with a store of its own, for a user on a stock daemon";
      "fine-grained.ghc-shim".via = "applied to this driver's ghc; the compiler a plan's configure records";
      "fine-grained.configure-flags".via = "each plan's configure flags, computed from the package's `packages.<name>` fields";
      "fine-grained.intermediates".via = "each plan derivation, whose output feeds mkDerivation `previousIntermediates`";

      "packages.*.src".via = "haskell.lib overrideSrc";

      "packages.*.previousIntermediates".via = "mkDerivation `previousIntermediates`; a fine-grained plan replaces it for the packages it selects";

      "shell.packages".via = "shellFor `packages`, selecting from the project's packages and source-repository-packages";
      "shell.tools".via = "resolved by name in `pkgs` and the Haskell package set (version requests are ignored; see `nixpkgs.options.tool-packages`)";
      "shell.buildInputs".via = "shellFor `buildInputs`";
      "shell.nativeBuildInputs".via = "shellFor `nativeBuildInputs`, after the resolved tools";
      "shell.shellHook".via = "shellFor `shellHook`";
      "shell.withHoogle".via = "shellFor `withHoogle`";
      "shell.crossPlatforms".via = "cross wrapper scripts from the selected `pkgsCross` compilers; full cross package sets under `project.projectCross`";

      cross-wrappers.via = "called with the wrapped cross compiler of every selected platform; the scripts join the shell's `nativeBuildInputs`";

      inputs.via = "`inputs.nixpkgs` supplies the package set; `inputs.haskell-nix` supplies the reused parsers";

    } // packageFields.vias
      // translations.common-vias {
        namespace = "nixpkgs";
        src-consumer = "local packages are built from";
      };
  };

}
