# The nixpkgs driver, assembled from the fragment files beside this one.
# Each fragment is a pure function over the context it needs.
#
# Builds the project with the Haskell infrastructure of nixpkgs
# (haskell.packages.<compiler>, callCabal2nix, haskell.lib) from the package
# set of `inputs.nixpkgs`. Everything nixpkgs-specific lives under the
# `nixpkgs` namespace:
#
# - driver knobs under `nixpkgs.options`
# - the result under `nixpkgs.project`
# - `nixpkgs.translation`, recording how every common option maps onto
#   nixpkgs
#
# This driver reuses haskell.nix's pure parsers (cabal-project-parser,
# host-map) for project interpretation. Its toolchain is involved only when
# `nixpkgs.options.use-plan` opts into cabal-exact discovery.

{ config, options, lib, pkgs, ... }:

with lib;
with (import ../../libs/prelude { inherit lib; });

let cfg = config.nixpkgs;

    # The common options, re-declared under this driver's namespace and
    # seeded from the top-level values, so setting
    # `nixpkgs.packages.foo.flags` overrides the common value for this
    # driver only. The driver reads all common configuration through the
    # mirror.
    common = import ../../libs/driver/common.nix {
      inherit lib pkgs cfg;
      driver = "nixpkgs";
      topConfig = config;
      topOptions = options;
    };
    compilers = common.compilers;
    compiler = compilers.native;

    platformsWithToolchain =
      filterAttrs (_: entry: entry.hasToolchain) compilers.platforms;

    crossSetFor = platform: import ../../libs/nixpkgs/cross-pkgs.nix {
      inherit lib platform;
      nixpkgs = config.inputs.nixpkgs;
      system = cfg.system;
      compiler = compilers.resolve platform;
      defaults = cfg.options.cross-package-defaults;
    };

in {

  options.nixpkgs = common.options
    // common.interface (import ./interface.nix { inherit lib cfg; })
    // import ./translation.nix { inherit lib; }
    // {

      pkgs = mkOption {
        type = types.raw;
        default = pkgs;
        defaultText = fenced-code ''import config.inputs.nixpkgs { inherit (config) system; }'';
        description = ''
          The nixpkgs package set the driver builds with.
        '';
        example = fenced-code ''import config.inputs.nixpkgs { inherit (config) system; overlays = [ my-overlay ]; }'';
      };

      default-compiler = mkOption {
        type = types.str;
        default = "ghc912";
        description = ''
          The `compiler.name` this driver falls back to when no
          `compiler.package` is set. A project's own `compiler.name`
          overrides it. No stackage snapshot covers ghc 9.14 yet, so the
          nixpkgs ghc914 package set has neither consistent bounds nor
          cached builds.
        '';
        example = "ghc910";
      };

      pkgsCross = mkOption {
        type = types.attrsOf types.raw;
        default = mapAttrs (platform: _: crossSetFor platform) platformsWithToolchain;
        defaultText = literalMD ''
          ```
          <nix-haskell>/libs/nixpkgs/cross-pkgs.nix
          ```
          for every `compiler.platforms` entry carrying a `toolchain`: a
          package set for that platform whose whole toolchain is the
          compiler's own, built non-static so a build can use the
          compiler's shared libraries. A platform without an entry gets
          none, and the driver falls back to `pkgs.pkgsCross.<platform>`.
        '';
        description = ''
          Cross package sets for `project.projectCross`, keyed by
          `pkgs.pkgsCross` platform name. An entry replaces the package set
          the driver would otherwise take from `pkgs.pkgsCross`. A compiler
          bringing its own toolchain needs the replacement, since that
          toolchain has to become the whole set's.
        '';
        example = fenced-code ''{ wasi32 = my-wasi-pkgs; }'';
      };

      haskellPackages = mkOption {
        type = types.raw;
        default = cfg.options.haskell-packages-for {
          inherit compiler;
          pkgs = config.nixpkgs.pkgs;
        };
        defaultText = literalMD ''
          ```
          config.nixpkgs.pkgs.haskell.packages.''${config.nixpkgs.compiler.name}
          ```
          A compiler package replaces that set's `ghc` instead, preferring
          the set of its own major.minor.patch version.
        '';
        description = ''
          The base Haskell package set, before the driver adds the
          project's packages and overrides.
        '';
        example = fenced-code ''pkgs.haskell.packages.ghc912'';
      };

      options = mkOption {
        default = {};
        description = ''
          nixpkgs-specific project options.
        '';
        type = types.submodule {
          options =
            import ./options.nix { inherit lib cfg; }
            // import ./hooks.nix { inherit lib pkgs config; };
        };
      };

      project = mkOption {
        type = types.raw;
        default = import ../../libs/nixpkgs/driver.nix {
          inherit lib;
          pkgs = config.nixpkgs.pkgs;
          haskellPackages = config.nixpkgs.haskellPackages;
          common = config.nixpkgs;
          options = config.nixpkgs.options;
          haskell-nix-src = config.inputs."haskell-nix";
          haskell-nix = config."haskell-nix";
          cross-wrappers = config.cross-wrappers;
        };
        defaultText = fenced-code ''
          import <nix-haskell>/libs/nixpkgs/driver.nix {
            inherit lib;
            pkgs = config.nixpkgs.pkgs;
            haskellPackages = config.nixpkgs.haskellPackages;
            common = config.nixpkgs;
            options = config.nixpkgs.options;
            haskell-nix-src = config.inputs."haskell-nix";
            haskell-nix = config."haskell-nix";
            cross-wrappers = config.cross-wrappers;
          }
        '';
        description = ''
          The built project: `packages` (the project's own packages),
          `haskellPackages` (the full extended set), `shell`, `projectCross`
          (per `pkgsCross` platform) and `ghcWithPackages`.
        '';
      };

  };

  config = mkMerge (common.mirror-config {
    namespace = "nixpkgs";
    defaultCompiler = cfg.default-compiler;
  } ++ [

    {
      # The one shell tool whose name is not the name of the package carrying
      # it. A definition rather than the option's `default`, so that a project
      # naming other tools keeps this entry.
      nixpkgs.options.tool-packages.cabal = mkOptionDefault cfg.pkgs.cabal-install;
    }

    {
      # This driver's own fine-grained steps. Driver defaults, so a
      # top-level definition or a `nixpkgs.fine-grained` one wins.
      nixpkgs.fine-grained = {
        configure-flags = common.mkDriverDefault
          (import ../../libs/nixpkgs/fine-grained/configure-flags.nix { inherit lib; });
        intermediates = common.mkDriverDefault
          (import ../../libs/nixpkgs/fine-grained/intermediates.nix { inherit lib; });
      };
    }

  ]);

}
