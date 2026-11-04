# The driver's own settings: what it discovers, what it relaxes for
# packages from outside the project, and what it puts in the shell. The
# steps that read these settings are the function-options in ./hooks.nix.
{ lib, cfg }:

with lib;
with (import ../../libs/common { inherit lib; });

let flagField = default: description: mkOption {
      type = types.bool;
      inherit default description;
    };

in {

  # --------------------------------------------------------------------------
  # Project structure
  # --------------------------------------------------------------------------

  packages = mkOption {
    type = types.nullOr (types.attrsOf (types.submodule {
      options.subdir = mkOption {
        type = types.str;
        default = ".";
        description = ''
          Directory of the package within the project source.
        '';
      };
    }));
    default = null;
    description = ''
      Explicit map of the project's local packages, keyed by cabal
      package name. The map replaces discovery.
    '';
    example = fenced-code ''
      {
        common.subdir = "common";
        frontend.subdir = "frontend";
      }
    '';
  };

  use-plan = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Take the project's structure (local packages, their
      directories, source-repository-packages) from the cabal
      plan of the haskell.nix driver instead of the root of the
      source. The plan is cabal's own reading of cabal.project,
      so globs, optional-packages and conditionals are exact.
      The cost is evaluating the haskell.nix toolchain (import
      from derivation). The driver still builds the packages
      from nixpkgs.

      This turns `exact-configuration` on by default. A plan
      brings in packages with version bounds this driver has no
      solver to satisfy, so reading a cabal.project needs the
      bound relief as well.
    '';
  };

  exact-configuration = mkOption {
    type = types.bool;
    default = cfg.options.use-plan;
    defaultText = literalMD "`nixpkgs.options.use-plan`";
    description = ''
      Tell Cabal every direct dependency, by the id its package
      database records, and every flag the package declares. Cabal
      then resolves nothing itself and reads no version bound.

      With no bounds read, a package builds against a compiler
      released after its cabal file was written. This includes a
      bound inside a conditional stanza, which `jailbreak` cannot
      reach.

      The haskell.nix driver configures every package this way.
      That is why `allow-newer` in a cabal.project takes effect in
      that driver and not in this one.

      A flag the project states in `packages.<name>.flags` still
      wins. The generated assignments go first, and Cabal takes
      the last assignment of a flag.

      The default follows `use-plan` unless the project sets this
      option. A plan read from a cabal.project brings in the
      packages that file's `allow-newer` was written for. This
      driver has no other way past their bounds. Set the option
      explicitly to break the link, in either direction.
    '';
  };

  # --------------------------------------------------------------------------
  # Defaults for packages the project does not carry
  # --------------------------------------------------------------------------

  extra-package-defaults = mkOption {
    default = {};
    description = ''
      Defaults applied to packages rooted outside the project
      source:

      - a `source-repository-packages` entry
      - a `hackage-overlays` entry

      This driver has no solver, so their version bounds usually
      need lifting.
    '';
    type = types.submodule {
      options = {
        jailbreak = flagField true "Lift version bounds (`haskell.lib.doJailbreak`).";
        check = flagField false "Run the test suites of these packages.";
        haddock = flagField false "Build the documentation of these packages.";
      };
    };
  };

  cross-package-defaults = mkOption {
    default = {};
    description = ''
      Defaults applied to every package of a cross set the driver
      builds itself (`nixpkgs.pkgsCross`), the set a compiler
      needs when it brings its own toolchain. The project's own
      `packages.<name>` settings take priority, since the driver
      applies them after. There is no field for tests or
      benchmarks. A cross set cannot run what it builds, so both
      stay off.
    '';
    type = types.submodule {
      options = {
        jailbreak = flagField true ''
          Lift version bounds (`haskell.lib.doJailbreak`). A cross
          set has no solver to satisfy them with.
        '';
        haddock = flagField false "Build documentation.";
        profiling = flagField false "Build profiling libraries.";
      };
    };
  };

  # --------------------------------------------------------------------------
  # Escape hatches
  # --------------------------------------------------------------------------

  package-arguments = mkOption {
    type = types.attrsOf (types.attrsOf types.raw);
    default = {};
    example = fenced-code ''{ reflex-todomvc.postInstall = "cp -r static $out"; }'';
    description = ''
      mkDerivation arguments set per package, applied with
      `overrideCabal` after every tweak the driver generates and
      before `overrides`. An entry replaces the argument's value
      whole. This covers arguments and phase hooks the `packages`
      fields do not name. The haskell.nix counterpart is a module
      in `haskell-nix.overrides`.
    '';
  };

  overrides = mkOption {
    type = types.listOf types.raw;
    default = [];
    description = ''
      Overlays over the Haskell package set (`self: super: { ... }`),
      applied after everything the driver generates, and before a
      fine-grained build wraps the result. Use it for anything the
      common options do not cover.
    '';
    example = fenced-code ''[ (self: super: { my-dep = pkgs.haskell.lib.dontCheck super.my-dep; }) ]'';
  };

  # --------------------------------------------------------------------------
  # Shell
  # --------------------------------------------------------------------------

  tool-packages = mkOption {
    type = types.attrsOf types.package;
    default = {};
    defaultText = fenced-code ''{ cabal = config.nixpkgs.pkgs.cabal-install; }'';
    description = ''
      Overrides for `shell.tools` resolution, keyed by tool name.
      The driver takes the first source that has the name:

      1. this map
      2. `pkgs.<name>`
      3. the Haskell package set

      It ignores version requests, since nixpkgs carries a single
      version. `cabal` is here because the tool's name is not the
      name of the package carrying it. An entry of the project's
      own replaces it.
    '';
    example = fenced-code ''{ haskell-language-server = pkgs.haskell-language-server; }'';
  };

  shellFor-args = mkOption {
    type = types.attrs;
    default = {};
    description = ''
      Extra arguments passed to `shellFor` verbatim
      (`extraDependencies`, `doBenchmark`, ...).
    '';
    example = { doBenchmark = true; };
  };

}
