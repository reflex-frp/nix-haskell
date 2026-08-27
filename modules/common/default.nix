# Driver-neutral project options, assembled from the fragment files
# beside this one. Each fragment is a pure function over the context it
# needs.
#
# Every driver honors every option in this module. The totality check
# compares these options against each driver's `translation` table. Adding
# an option here without teaching every driver about it fails evaluation.
# Anything only one driver can honor belongs in that driver's own module
# instead.

# `topConfig` is the project's own config: `config` itself at the top level,
# and the enclosing project when a driver mirrors this module for itself.
# Options settled once for the whole project rather than per driver come
# from it. The bundle optimizers live outside this module, so a mirror has
# no declaration of them to read.
{ config, lib, pkgs, topConfig ? config, ... }:

with lib;

let mkDriverDefault = import ../../libs/driver/priority.nix { inherit lib; };

    packageFields = import ../../libs/package-fields.nix { inherit lib; };

    # One layer of the bundle optimizer settings, nullable throughout. The
    # values live in the top-level `wasm-opt` and `closure-compiler`, and a
    # `null` here states nothing, so the layer beneath decides.
    # `wasm-optimize` and `js-optimize` resolve the layers, and they are the
    # only readers, so no driver needs to know about them.
    bundleOptimizerLayer = import ../../libs/bundle-optimizer/options.nix {
      inherit lib;
      inherits = "the layer beneath it, and last to the tool's own settings at the top level";
    };

    # The same layer for tools this repo does not bundle: they have no typed
    # options to inherit, so their fields ride as raw values.
    bundleOptimizersOption = mkOption {
      type = types.attrsOf (types.attrsOf types.raw);
      default = {};
      example = { probe-opt.level = 2; };
      description = ''
        Settings layers for optimizer tools a project registered through an
        imported cross-target module: tool name, then field, then value.
        The bundled tools use their typed `wasm-opt` and `closure-compiler`
        options beside this instead. A field absent here states nothing.
      '';
    };

    bundleFields = import ./bundle-fields.nix { inherit lib config topConfig; };

    packagesOptions = import ./packages.nix {
      inherit lib packageFields bundleOptimizerLayer bundleOptimizersOption;
    };

in {

  options =
    import ./project.nix { inherit lib config; }
    // import ./src.nix { inherit lib pkgs config; }
    // import ./cabal-project.nix { inherit lib; }
    // import ./compiler.nix { inherit lib; }
    // import ./fine-grained.nix { inherit lib config topConfig; }
    // packagesOptions
    # `platforms` carries the `packages` option itself, not a copy, so this
    # import threads in the packages fragment's result.
    // import ./platforms.nix {
         inherit lib bundleFields bundleOptimizerLayer bundleOptimizersOption;
         inherit (packagesOptions) packages;
       }
    // import ./shell.nix { inherit lib; }
    // import ./external-packages.nix { inherit lib; };

  config = {

    shell = {

      tools = {
        # Each driver's mirror re-applies this definition, where it must
        # stay below the seeds carrying the top-level values.
        cabal = mkDriverDefault "latest";
      };

    };

  };

}
