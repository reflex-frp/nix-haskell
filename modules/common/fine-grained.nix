# Fine-grained builds. Sandstone makes one derivation for each module with
# Nix dynamic derivations. The package build then resumes from the result
# and only links. While `enable` is off, a stock Nix reads none of this.
#
# The option is common, so both drivers read it, each through its own
# mirror. `nixpkgs.fine-grained.<field>` or `haskell-nix.fine-grained.<field>`
# overrides a field for that driver only. The `sandstone` default reads
# `topConfig.inputs`: a driver mirror's `config` carries no `inputs`.
{ lib, config, topConfig }:

with lib;
with (import ../../libs/prelude { inherit lib; });

{

  fine-grained = mkOption {
    default = {};
    description = ''
      Builds the selected packages one module at a time, so that a change
      to one module rebuilds one module. Evaluation reads
      `builtins.outputOf`, and the builds need the Nix of `nix` below.

      The modules hold the ways of one `Setup build`, so a package that
      keeps `packages.<name>.enableLibraryProfiling` on compiles every
      module a second time. The drivers warn when that happens.
    '';
    type = types.submodule {
      options = {

        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to build the packages `packages` names module by
            module. Off leaves the drivers' own build paths in place.
          '';
        };

        packages = mkOption {
          type = types.nullOr (types.listOf types.str);
          default = null;
          defaultText = literalMD "every local package";
          example = [ "frontend" "common" ];
          description = ''
            The packages built module by module, by cabal package name.
            `null` takes every local package, and `[]` takes none. Cross
            platforms are never built this way.
          '';
        };

        sandstone = mkOption {
          type = types.raw;
          default = import topConfig.inputs.sandstone {
            nixpkgsArgs = {
              localSystem = {
                system = config.system;
              };
            };
          };
          defaultText = fenced-code ''
            import config.inputs.sandstone {
              nixpkgsArgs = {
                localSystem = {
                  system = config.system;
                };
              };
            }
          '';
          description = ''
            The sandstone checkout, read with the nixpkgs and the Nix
            overlay that it pins itself. Those are not a driver's, and
            these builds use only the tool that it carries.
          '';
        };

        tool = mkOption {
          type = types.package;
          default = config.fine-grained.sandstone.haskellPackages.sandstone;
          defaultText = fenced-code ''<sandstone>.haskellPackages.sandstone'';
          description = ''
            The package that carries `bin/cabal-dyn-drv`, which builds
            every plan.
          '';
        };

        nix = mkOption {
          type = types.package;
          default = config.fine-grained.sandstone.nix;
          defaultText = fenced-code ''<sandstone>.nix'';
          description = ''
            The Nix that these builds need, with dynamic derivations and
            the `builder-rpc-v0` system feature. Build it and run it as
            the daemon, or drive a store of its own with it.
          '';
        };

        ghc-shim = function-option {
          result = types.package;
          default = import ../../libs/fine-grained/ghc-shim.nix;
          defaultText = fenced-code ''<nix-haskell>/libs/fine-grained/ghc-shim.nix'';
          description = ''
            The compiler that a plan's configure records, so that
            sandstone reads the flags Cabal computed. The call carries
            `pkgs` and `ghc`, and each driver passes its own compiler.
          '';
        };

        configure-flags = function-option {
          result = types.str;
          defaultText = fenced-code ''
            <nix-haskell>/libs/nixpkgs/fine-grained/configure-flags.nix
            <nix-haskell>/libs/haskell-nix/fine-grained/configure-flags.nix
          '';
          description = ''
            The configure flags of one package's plan, one step per
            driver. The nixpkgs call carries `name`, `tweaks`,
            `ghc-options`, `ghc` and `pkgs`. The haskell.nix call carries
            `name`, `component`, `ghc` and `pkgs`.

            The flags must make configure compute the ghc flags that the
            package's own configure computes. A mismatch costs
            recompilation. Replace this step where something the default
            cannot read changes a build way, such as the nixpkgs driver's
            `package-arguments` or `overrides`.
          '';
          example = fenced-code ''
            args: import "''${nix-haskell-libs}/nixpkgs/fine-grained/configure-flags.nix" { inherit lib; } args
              + " --ghc-option=-fno-ignore-asserts"
          '';
        };

        intermediates = function-option {
          result = types.raw;
          defaultText = fenced-code ''
            <nix-haskell>/libs/nixpkgs/fine-grained/intermediates.nix
            <nix-haskell>/libs/haskell-nix/fine-grained/intermediates.nix
          '';
          description = ''
            Builds one package's plan, the derivation whose output is the
            derivation that assembles that package's modules. One step
            per driver. The nixpkgs call carries `name`, `package`,
            `dependencies`, `ghc`, `shim`, `tool`, `configure-flags` and
            `pkgs`. The haskell.nix call carries `name`, `version`,
            `src`, `subdir`, `setup`, `config-files`, `build-flags`,
            `ghc`, `shim`, `tool`, `configure-flags` and `pkgs`.
          '';
          example = fenced-code ''
            args: import "''${nix-haskell-libs}/nixpkgs/fine-grained/intermediates.nix" { inherit lib; }
              (args // { configure-flags = args.configure-flags + " --enable-tests"; })
          '';
        };

      };
    };
  };

}
