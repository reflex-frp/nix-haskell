# The driver's pipeline steps, each an overridable function. Replace one
# step and the others stay as they are. Each default is what the driver
# does on its own. The sections are the driver's stages.
{ lib, pkgs, config }:

with lib;
with (import ../../libs/common { inherit lib; });

{

  # --------------------------------------------------------------------------
  # Project interpretation
  # --------------------------------------------------------------------------

  discover-packages = function-option {
    result = types.attrsOf types.attrs;
    default = (import ../../libs/nixpkgs/project-file.nix {
      inherit pkgs;
      haskell-nix-src = config.inputs."haskell-nix";
    }).discover;
    defaultText = fenced-code ''<nix-haskell>/libs/nixpkgs/project-file.nix: discover'';
    description = ''
      Finds the project's local packages. The result is
      `{ <name> = { subdir; src; }; }`. The call carries:

      - `src`, the cleaned project source
      - `explicit`, the `packages` option's map, `null` when
        unset

      The default takes, in order:

      1. `explicit`, resolved against `src`
      2. the one package at the root of `src`

      It throws when there is neither. Replace it for a layout
      the default cannot find, such as globs or a multi-package
      tree with no explicit map.
    '';
    example = fenced-code ''
      { src, explicit }: {
        frontend = { subdir = "frontend"; src = src + "/frontend"; };
        backend = { subdir = "backend"; src = src + "/backend"; };
      }
    '';
  };

  project-text = function-option {
    result = types.str;
    default = import ../../libs/nixpkgs/project-text.nix { inherit lib; };
    defaultText = fenced-code ''<nix-haskell>/libs/nixpkgs/project-text.nix'';
    description = ''
      Assembles the project text the driver reads
      `source-repository-package` stanzas from. The call carries:

      - `projectFile`, the project file's text, `null` when there
        is none
      - `cabalProject`
      - `cabalProjectLocal`
      - `extraCabalProject`

      In the default `cabalProject` replaces the file text, and
      `cabalProjectLocal` and the `extraCabalProject` lines
      follow it.
    '';
    example = fenced-code ''
      { projectFile, extraCabalProject, ... }:
        lib.concatStringsSep "\n" (lib.optional (projectFile != null) projectFile ++ extraCabalProject)
    '';
  };

  evaluate-condition = function-option {
    result = types.bool;
    default = { condition, hostMap }:
      import ../../libs/nixpkgs/condition.nix {
        inherit lib hostMap;
        compiler-version = config.nixpkgs.compiler-version;
      } condition;
    defaultText = fenced-code ''<nix-haskell>/libs/nixpkgs/condition.nix'';
    description = ''
      Evaluates the `condition` of a `source-repository-packages`
      entry against the target platform. The call carries:

      - `condition`, the condition string
      - `hostMap`, haskell.nix's map for the platform, holding
        its cabal `os` and `arch` names

      The default handles `os(..)`, `arch(..)`, `impl(ghc ..)`,
      `!`, `&&`, `||` and parentheses. It assumes `flag(..)` and
      any other `impl(..)` hold, with a warning.
    '';
    example = fenced-code ''
      { condition, hostMap }:
        if condition == "flag(js-backend)"
        then true
        else import "''${nix-haskell-libs}/nixpkgs/condition.nix" { inherit lib hostMap; } condition
    '';
  };

  fetch-stanza-source = function-option {
    result = types.raw;
    default = import ../../libs/nixpkgs/fetch-stanza-source.nix { inherit lib; };
    defaultText = fenced-code ''<nix-haskell>/libs/nixpkgs/fetch-stanza-source.nix'';
    description = ''
      Fetches the source a cabal.project
      `source-repository-package` stanza names. The call carries:

      - `stanza`, the parsed stanza, with its `url`, `ref` or
        `rev`, `sha256` and `subdirs`
      - `inputMap`
      - `pkgs`

      The default takes, in order:

      1. `inputMap."<url>/<rev>"` (rev falls back to the ref)
      2. `inputMap.<url>`
      3. `pkgs.fetchgit`, when the stanza carries a sha256
      4. `builtins.fetchGit`

      Replace it to fetch through another tool or a mirror.
    '';
    example = fenced-code ''
      { stanza, inputMap, pkgs }:
        inputMap.''${stanza.url} or (throw "unpinned source-repository-package: ''${stanza.url}")
    '';
  };

  # --------------------------------------------------------------------------
  # The package set
  # --------------------------------------------------------------------------

  haskell-packages-for = function-option {
    result = types.raw;
    default = { pkgs, compiler }:
      import ../../libs/nixpkgs/haskell-packages.nix { inherit lib pkgs compiler; };
    defaultText = fenced-code ''<nix-haskell>/libs/nixpkgs/haskell-packages.nix'';
    description = ''
      The base Haskell package set for one platform, before the
      driver adds the project's packages and overrides. The call
      carries:

      - `pkgs`, that platform's package set
      - `compiler`, its resolved compiler entry

      `haskellPackages` replaces the native set only. This
      function also builds the set of every cross platform.
    '';
    example = fenced-code ''{ pkgs, compiler }: pkgs.haskell.packages.''${compiler.stockName}'';
  };

  cabal2nix-options = function-option {
    result = types.str;
    default = import ../../libs/nixpkgs/cabal2nix-options.nix { inherit lib; };
    defaultText = fenced-code ''<nix-haskell>/libs/nixpkgs/cabal2nix-options.nix'';
    description = ''
      Builds the option string `callCabal2nixWithOptions`
      generates a package expression with. The call carries:

      - `name`, the package name
      - `external`, true for a package rooted outside the project
      - `tweaks`, the platform-merged `packages` entry, `{}` when
        there is none
      - `extra-package-defaults`

      The default emits `--flag`,
      `--no-check` and `--no-haddock`. Replace it to add a flag
      nothing else emits, such as `--jailbreak`, `--benchmark` or
      `--hpack`.
    '';
    example = fenced-code ''
      args: "--jailbreak " + import "''${nix-haskell-libs}/nixpkgs/cabal2nix-options.nix" { inherit lib; } args
    '';
  };

  package-steps = function-option {
    result = types.listOf types.raw;
    default = import ../../libs/nixpkgs/package-steps.nix { inherit lib; };
    defaultText = fenced-code ''<nix-haskell>/libs/nixpkgs/package-steps.nix'';
    description = ''
      The `drv -> drv` steps that apply a package's `packages`
      entry, in order. The call carries:

      - `name`, the package name
      - `tweaks`, the platform-merged `packages` entry
      - `generated`, true when cabal2nix generated the expression
        and already applied its cabal flags
      - `compose`, the set's `haskell.lib.compose`

      Replace it to add a step, reorder the steps, or apply a
      field the shipped steps do not know.
    '';
    example = fenced-code ''
      args: import "''${nix-haskell-libs}/nixpkgs/package-steps.nix" { inherit lib; } args
        ++ [ args.compose.disableLibraryProfiling ]
    '';
  };

  exact-configuration-hook = function-option {
    result = types.lines;
    default = { ghc }: import ../../libs/nixpkgs/exact-configuration.nix { inherit ghc; };
    defaultText = fenced-code ''<nix-haskell>/libs/nixpkgs/exact-configuration.nix'';
    description = ''
      The shell text `exact-configuration` appends to each
      package's `preConfigure`. The text assembles the exact
      `--dependency` list from the compiler's package databases,
      so cabal resolves against installed packages instead of
      version bounds. The call carries `ghc`, the executable name
      the script reads the databases with. The hook runs only
      while `exact-configuration` is on.
    '';
    example = fenced-code ''
      args: import "''${nix-haskell-libs}/nixpkgs/exact-configuration.nix" args + "echo exact configuration written\n"
    '';
  };

  project-overlays = function-option {
    result = types.listOf types.raw;
    default = { overlays }: overlays;
    defaultText = fenced-code ''{ overlays }: overlays'';
    description = ''
      The overlays that extend the package set. The call's
      `overlays` field carries every generated overlay, with
      `overrides` last and a fine-grained wrap after it. Replace
      it to prepend, reorder, drop or wrap them.
    '';
    example = fenced-code ''{ overlays }: [ (self: super: { chrome-test-utils = null; }) ] ++ overlays'';
  };

  # --------------------------------------------------------------------------
  # Shell
  # --------------------------------------------------------------------------

  resolve-shell-tool = function-option {
    default = import ../../libs/nixpkgs/resolve-shell-tool.nix { inherit lib; };
    defaultText = fenced-code ''<nix-haskell>/libs/nixpkgs/resolve-shell-tool.nix'';
    description = ''
      Resolves one `shell.tools` entry to the package that provides
      it. The call carries:

      - `name`, the tool's name
      - `request`, the entry's value, a version request
      - `tool-packages`
      - `pkgs`
      - `haskellPackages`, the project's extended set

      The default ignores the request, because honoring one needs
      a solver. It takes the first source that has the name, and
      throws when none does.
    '';
    example = fenced-code ''{ name, haskellPackages, ... }: haskellPackages.''${name}'';
  };

  cross-ghc-env = function-option {
    default = { ghc, packages, pkgs }:
      import ../../libs/nixpkgs/cross-ghc-env.nix { inherit pkgs lib; } { inherit ghc packages; };
    defaultText = fenced-code ''<nix-haskell>/libs/nixpkgs/cross-ghc-env.nix'';
    description = ''
      Wraps a cross compiler with the given packages in its
      package database, the cross counterpart of `shellFor`'s
      native environment. The call carries:

      - `ghc`, the cross compiler
      - `packages`, the packages to register
      - `pkgs`, what the wrapper is built with

      The default does not use `ghcWithPackages`. That
      function aims the compiler at a library directory named
      after the version, so it cannot wrap a relocatable bindist.
    '';
    example = fenced-code ''{ ghc, packages, pkgs }: ghc'';
  };

  shell-arguments = function-option {
    result = types.attrs;
    default = { args }: args;
    defaultText = fenced-code ''{ args }: args'';
    description = ''
      The arguments the shell is built from. That is what
      `shellFor` receives, with `shellFor-args` already merged in.
      Replace it to edit a field in place. The same field set
      through `shellFor-args` replaces the whole field.
    '';
    example = fenced-code ''{ args }: args // { nativeBuildInputs = args.nativeBuildInputs ++ [ pkgs.sqlite ]; }'';
  };

}
