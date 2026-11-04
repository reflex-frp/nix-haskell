# The per-package fields, stated once for every consumer:
# 1. `options` declares them (the `packages.<name>` submodule).
# 2. `names` keys the drivers' translation tables.
# 3. `args` maps a field to the mkDerivation argument the nixpkgs driver
#    writes.
# 4. `vias` states how the nixpkgs driver honors each field.
# Adding a field is one row here. A row without `arg` is written by a
# dedicated translation step, and its `via` says which.
#
# Example:
#
#   fields = import ./package-fields.nix { inherit lib; };
#
#   fields.names
#   => [ "flags" "patches" ... "hardeningDisable" "preUnpack" ... ]
#
#   fields.args.doHyperlinkSource
#   => "hyperlinkSource"
#
#   fields.vias."packages.*.enableShared"
#   => { via = "mkDerivation `enableSharedLibraries`"; }
{ lib }:

with lib;
with (import ./common { inherit lib; });

let buildPhases = build-phases;

    # ------------------------------------------------------------------------
    # Generators
    # ------------------------------------------------------------------------

    setupFlags = phase: mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        Extra flags passed to `Setup ${phase}`.
      '';
      example = [ "-v" ];
    };

    nullableOption = row: mkOption ({
      type = row.type or (types.nullOr types.bool);
      default = null;
      description = "${row.description} `null` leaves the default in place.\n";
    } // optionalAttrs (row ? example) { inherit (row) example; });

    phaseHook = pre: phase:
      nameValuePair "${if pre then "pre" else "post"}${phase}" (mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = ''
          Shell code run ${if pre then "before" else "after"} the
          ${toLower phase} phase. `null` leaves the default in
          place.
        '';
        example = "export HOME=$TMPDIR";
      });

    phaseHookOptions =
      listToAttrs (concatMap (phase: [ (phaseHook true phase) (phaseHook false phase) ])
        buildPhases.names);

    # ------------------------------------------------------------------------
    # The fields
    # ------------------------------------------------------------------------

    # The fields whose empty value ({} or []) already means "nothing
    # stated". Each carries its own declaration and via.
    statedRows = [

      { name = "flags";
        via = "`--flag` cabal2nix options for generated packages, enableCabalFlag/disableCabalFlag otherwise";
        option = mkOption {
          type = types.attrsOf types.bool;
          default = {};
          description = ''
            Cabal flag assignments for the package (`true` enables,
            `false` disables).
          '';
          example = { use-warp = true; webkit2gtk = false; };
        };
      }

      { name = "patches";
        via = "haskell.lib appendPatches";
        option = mkOption {
          type = types.listOf types.path;
          default = [];
          description = ''
            Patches applied to the package source.
          '';
          example = fenced-code ''[ ./splitmix.patch ]'';
        };
      }

      { name = "ghcOptions";
        via = "`--ghc-option` configure flags";
        option = mkOption {
          type = types.listOf types.str;
          default = [];
          description = ''
            GHC flags for this package only.
          '';
          example = [ "-Wall" "-Werror" ];
        };
      }

      { name = "configureFlags";
        via = "haskell.lib appendConfigureFlags";
        option = setupFlags "configure";
      }

      { name = "setupBuildFlags";
        via = "mkDerivation `buildFlags`";
        option = setupFlags "build";
      }

      { name = "setupHaddockFlags";
        via = "mkDerivation `haddockFlags`";
        option = setupFlags "haddock";
      }

    ];

    # The "`null` leaves the default in place" family. `type` defaults to a
    # nullable bool.
    nullableRows = [
      { name = "doCheck"; arg = "doCheck";
        description = "Whether to run the package's test suites."; }
      { name = "doHaddock"; arg = "doHaddock";
        description = "Whether to build the package's documentation."; }
      { name = "doCoverage"; arg = "doCoverage";
        description = "Whether to generate a coverage report for the package."; }
      { name = "doHoogle"; arg = "doHoogle";
        description = "Whether to generate a hoogle index for the package's documentation."; }
      { name = "doHyperlinkSource"; arg = "hyperlinkSource";
        description = "Whether to generate hyperlinked source code alongside the package's documentation."; }
      { name = "doQuickjump"; arg = "doHaddockQuickjump";
        description = "Whether to generate the quickjump index of the package's documentation."; }
      { name = "dontStrip"; arg = "dontStrip";
        description = "Whether to leave the produced binaries unstripped."; }
      { name = "enableDeadCodeElimination"; arg = "enableDeadCodeElimination";
        description = "Whether to eliminate unused code at link time."; }
      { name = "enableLibraryProfiling"; arg = "enableLibraryProfiling";
        description = "Whether to build the package's library with profiling support."; }
      { name = "enableProfiling";
        via = "mkDerivation `enableLibraryProfiling` and `enableExecutableProfiling`";
        description = "Whether to build the whole package with profiling support."; }
      { name = "profilingDetail"; arg = "profilingDetail";
        type = types.nullOr types.str;
        example = "toplevel-functions";
        description = "The profiling detail level."; }
      { name = "enableShared"; arg = "enableSharedLibraries";
        description = "Whether to build a shared library."; }
      { name = "enableStatic"; arg = "enableStaticLibraries";
        description = "Whether to build a static library."; }
      { name = "enableSeparateDataOutput"; arg = "enableSeparateDataOutput";
        description = "Whether to install the package's data files into a separate output."; }
      { name = "enableLibraryForGhci"; arg = "enableLibraryForGhci";
        description = "Whether to build a pre-linked object of the library for loading into GHCi."; }
      { name = "hardeningDisable"; arg = "hardeningDisable";
        type = types.nullOr (types.listOf types.str);
        example = [ "format" ];
        description = "Hardening flags to disable when building the package."; }
    ];

in {

  # --------------------------------------------------------------------------
  # What each consumer reads
  # --------------------------------------------------------------------------

  names =
    map (row: row.name) (statedRows ++ nullableRows)
    ++ buildPhases.hooks;

  options =
    listToAttrs (map (row: nameValuePair row.name row.option) statedRows)
    // listToAttrs (map (row: nameValuePair row.name (nullableOption row)) nullableRows)
    // phaseHookOptions;

  args =
    listToAttrs
      (map (row: nameValuePair row.name row.arg)
        (filter (row: row ? arg) nullableRows))
    // genAttrs buildPhases.hooks id;

  vias =
    listToAttrs
      (map
        (row: nameValuePair "packages.*.${row.name}"
          { via = row.via or "mkDerivation `${row.arg}`"; })
        (statedRows ++ nullableRows))
    // listToAttrs
      (map
        (hook: nameValuePair "packages.*.${hook}" { via = "mkDerivation `${hook}`"; })
        buildPhases.hooks);

}
