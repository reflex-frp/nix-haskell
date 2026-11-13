# A driver's `translation` table: one entry per user-settable common
# option, stating how the driver honors it.
#
# The keys are the contract. The totality check compares each driver's key
# set against the common options in both directions. A common option a
# driver does not translate fails evaluation, and so does a stale entry for
# a removed option. `shell` and `packages` sub-options get their own keys
# ("shell.tools", "packages.*.flags", ...), so a new sub-option trips the
# check too.
#
# Example of a value of the type:
#
#   {
#     "compiler.name" = {
#       set = { compiler-nix-name = compiler.name; };
#       via = "project `compiler-nix-name`";
#     };
#     clean-src.via = "consumed by `src-cleaned`";   # set = null: no payload
#   }
#
# Example of a declaration:
#
#   translations.declare {
#     driver = "nixpkgs";
#     default = { ... } // translations.common-vias {
#       namespace = "nixpkgs";
#       src-consumer = "local packages are built from";
#     };
#   }
#   => <the read-only internal `translation` option>
{ lib }:

with lib;

let type = types.attrsOf (types.submodule {
      options = {
        set = mkOption {
          type = types.nullOr types.raw;
          default = null;
          internal = true;
          description = ''
            Definition set merged into the driver's `options` submodule. `null`
            when the common option is consumed elsewhere, as `via` says.
          '';
        };
        via = mkOption {
          type = types.str;
          internal = true;
          description = ''
            How the common option is honored by this driver.
          '';
        };
      };
    });

in {

  inherit type;

  # The `translation` option, declared the same way by every driver.
  # `extra` carries a driver's own sentence, placed before the shared one.
  declare = { driver, default, extra ? "" }:
    mkOption {
      inherit type default;
      readOnly = true;
      internal = true;
      description = ''
        How each common option maps onto ${driver}. ${extra}The keys are
        compared against the common options by the totality check.
      '';
    };

  # The entries that read the same for every driver: options no driver
  # builds anything for, honored the same way everywhere. `namespace` is
  # the driver namespace whose `cross-compiler` wasm-jsffi names, and
  # `src-consumer` completes the clean-src sentence.
  common-vias = { namespace, src-consumer }:
    let src-cleaned = "consumed by `src-cleaned`, which ${src-consumer}";
    in {
      clean-src.via = src-cleaned;
      clean-src-ignore-files.via = src-cleaned;
      clean-src-patterns.via = src-cleaned;

      "compiler.targetPrefix".via = "spliced onto the compiler as `ghc.targetPrefix`, which names every tool the builders call";

      optimizations.via = "writes the common `ghcOptions` option";
      isGhcjs.via = "adds nodejs to the common `shell.buildInputs`";
      isWasm.via = "adds nodejs to the common `shell.buildInputs`";

      wasm-opt.via = "nothing the driver builds; read by `wasm-optimize`";
      closure-compiler.via = "nothing the driver builds; read by `js-optimize`";
      "platforms.*.bundle-optimizers".via = "nothing the driver builds; read by a registered target's optimize function";
      "packages.*.bundle-optimizers".via = "nothing the driver builds; read by a registered target's optimize function";
      wasm-optimize.via = "applied by the project to a wasm binary the driver has already built";
      js-optimize.via = "applied by the project to a jsexe the driver has already built";
      wasm-jsffi.via = "applied by the project to a wasm binary the driver has already built, with the compiler `${namespace}.cross-compiler` names";
    };

}
