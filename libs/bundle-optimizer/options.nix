# The settings every bundle optimizer takes, keyed by tool. Each tool's
# fields are its own flags, so a layer is checked against the vocabulary
# that reads it. A caller declaring a whole layer names this set once
# instead of naming each tool. With `inherits` set, every field becomes
# nullable: `null`
# states nothing, and the field falls to the layer the `inherits` text
# names.
#
# Example:
#
#   import ./options.nix { inherit lib; }
#   => { wasm-opt         = { enable = <bool, default true>;
#                             level  = <enum [ "0" "1" "2" "3" "4" "s" "z" ], default "2">;
#                             extraFlags = <listOf str>; };
#        closure-compiler = { enable = <bool, default true>;
#                             level  = <enum [ "BUNDLE" ... "ADVANCED" ], default "ADVANCED">;
#                             externs = <listOf path, default []>;
#                             extraFlags = <listOf str>; };
#      }
#
#   import ./options.nix {
#     inherit lib;
#     inherits = "the setting for this package whatever the target";
#   }
#   => the same two field sets, every field nullable and defaulting to
#      `null`, its description saying what `null` leaves it to
{ lib, inherits ? null }:

with lib;
with (import ../common { inherit lib; });

let field = import ./field.nix { inherit lib inherits; };

    tools = {

      # ----------------------------------------------------------------------
      # wasm-opt
      # ----------------------------------------------------------------------

      wasm-opt = {

        enable = {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether `wasm-optimize` runs wasm-opt and the strip that follows it.
            When false, `wasm-optimize` copies its input through, so a caller
            installs the same path either way.
          '';
        };

        level = {
          type = lib.types.enum [ "0" "1" "2" "3" "4" "s" "z" ];
          default = "2";
          description = ''
            The `-O` level wasm-opt runs at.
          '';
          example = "z";
        };

        extraFlags = {
          type = lib.types.listOf lib.types.str;
          default = [ "-ol 2" "-s 1" "--low-memory-unused" "--strip-dwarf" "--converge" ];
          description = ''
            Flags appended after `-all -O<level>`, so one of these overrides what
            the level sets. Write one flag per element, with its value in the same
            string. The elements are joined into one command line.

            The default flags set the optimize level of `-O2` at the shrink level
            of `-O1`, drop the memory a module never reads, discard debug
            information, and repeat the passes until they find nothing more.
          '';
          example = [ "--enable-bulk-memory" ];
        };

      };

      # ----------------------------------------------------------------------
      # closure-compiler
      # ----------------------------------------------------------------------

      closure-compiler = {

        enable = {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether `js-optimize` runs closure-compiler. When false, `js-optimize`
            copies the jsexe through unchanged.
          '';
        };

        level = {
          type = lib.types.enum [ "BUNDLE" "WHITESPACE_ONLY" "SIMPLE" "TRANSPILE_ONLY" "ADVANCED" ];
          default = "ADVANCED";
          description = ''
            The `--compilation_level` closure-compiler runs at.
          '';
          example = "SIMPLE";
        };

        externs = {
          type = lib.types.listOf lib.types.path;
          default = [];
          description = ''
            Files passed as `--externs`. They declare what the program reaches by
            a name the compiler must not rename. The jsexe's own `all.externs.js`
            always goes ahead of these, since ADVANCED renames everything it is
            not told the runtime knows by name.
          '';
          example = fenced-code ''[ ./externs.js ]'';
        };

        extraFlags = {
          type = lib.types.listOf lib.types.str;
          default = [
            "--language_in UNSTABLE"
            "--warning_level QUIET"
            "--isolation_mode IIFE"
            "--assume_function_wrapper"
            "--emit_use_strict"
            "--jscomp_off=undefinedVars"
          ];
          description = ''
            Flags appended after the level and the externs, so one of these
            overrides what they set. Write one flag per element, with its value in
            the same string. The elements are joined into one command line.

            The default flags accept whatever syntax the linker emitted, keep the
            compiler quiet, wrap the program in a function expression it may
            assume nothing escapes from, ask for strict mode, and silence the
            warning about names the runtime defines elsewhere.
          '';
          example = [ "--formatting PRETTY_PRINT" ];
        };

      };

    };

in builtins.mapAttrs (_: fields: builtins.mapAttrs (_: field) fields) tools
