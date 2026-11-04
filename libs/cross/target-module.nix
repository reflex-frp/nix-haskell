# One cross-target module: from the name of a bundled row in
# ./targets.nix, or from a full row of the same shape. It declares:
# - The `is<Target>` flag: whether the project targets it, natively or
#   through `shell.crossPlatforms`.
# - The optimizer settings option: from ../bundle-optimizer/options.nix for
#   a bundled row, from the row's own `optimizer-fields` otherwise.
# - The optimize function-option, running the row's run function with the
#   settings the named target, package and executable resolve to.
# - Node.js in the shell while the flag is on, unless the row carries
#   `node = false`.
# The row also registers in the internal `cross-targets` option, which the
# bundle fields dispatch over.
#
# Example:
#
#   imports = [ (import ./target-module.nix "wasm") ];
#
#   imports = [ (import ./target-module.nix myRow) ];
target:

{ config, lib, pkgs, ... }:

with lib;
with (import ../common { inherit lib; });

let rows = import ./targets.nix { inherit lib; };

    # ------------------------------------------------------------------------
    # The row
    # ------------------------------------------------------------------------

    unknownTarget = throw ((message-prefix {}) "no cross target named \"${target}\"");

    given =
      if builtins.isString target
      then findFirst (row: row.name == target) unknownTarget rows
      else target;

    row =
      { matches = t: t.${given.flag} or false;
        node = true;
        optimizer-fields = null;
        optimize-defaultText = null;
      } // given;

    bundleOptimizer = import ../bundle-optimizer/options.nix { inherit lib; };

    field = import ../bundle-optimizer/field.nix { inherit lib; };

    bundleSettings = import ../bundle-optimizer/settings.nix { inherit lib; };

    crossPlatform = import ./platform.nix { inherit lib; };

in {

  options = {

    # ------------------------------------------------------------------------
    # The flag
    # ------------------------------------------------------------------------

    ${row.flag} = mkOption {
      type = types.bool;
      default =
        let selected = config.shell.crossPlatforms (crossPlatform.probe pkgs);
        in row.matches pkgs.stdenv.hostPlatform
           || row.selected selected;
      defaultText = literalMD row.selectedText;
      description =
        if row.node
        then ''
          Whether the project targets ${row.target}, natively or through
          cross-compilation. When true, Node.js joins
          `shell.buildInputs`.
        ''
        else ''
          Whether the project targets ${row.target}, natively or through
          cross-compilation.
        '';
    };

    # ------------------------------------------------------------------------
    # The optimizer
    # ------------------------------------------------------------------------

    ${row.optimizer} =
      if row.optimizer-fields == null
      then bundleOptimizer.${row.optimizer}
      else mapAttrs (_: field) row.optimizer-fields;

    ${row.optimize} = function-option {
      default = row.mkOptimize {
        inherit pkgs lib;
        settings = keys: bundleSettings ({
          tool = row.optimizer;
          defaults = config.${row.optimizer};
          inherit (config) packages platforms;
        } // keys);
      };
      defaultText =
        if row.optimize-defaultText != null
        then row.optimize-defaultText
        else fenced-code "<nix-haskell>/libs/${row.runPath}, run with the settings the named target, package and executable resolve to";
      description = ''
        ${row.lead}

        ```
        ${row.optimize} {
          platform = "${row.examplePlatform}";
          package = "frontend";
          exe = "frontend";
          ${row.artifact} = "''${frontend}/bin/frontend${row.extension}";
        }
        ```

        `platform`, `package` and `exe` are only lookup keys for the
        settings. Each can be left out, and an omitted key states nothing.

        Each field of the `${row.optimizer}` settings resolves on its own.
        The most specific layer that states a field decides it, in this
        order:

        1. `platforms.<platform>.packages.<package>.components.exes.<exe>.${row.optimizer}`
        2. `platforms.<platform>.packages.<package>.${row.optimizer}`
        3. `platforms.<platform>.${row.optimizer}`
        4. `packages.<package>.components.exes.<exe>.${row.optimizer}`,
           then `packages.<package>.${row.optimizer}`
        5. `${row.optimizer}` at the top level, the only layer that holds
           every field.

        The settings come from the project's own values, not a driver's.
        This function runs on a built artifact, outside any driver.
      '';
    };

  };

  config = {

    cross-targets.${row.name} = row;

    shell = {

      # Template Haskell needs Node.js. The slim build is enough, since it
      # runs only the runtime, never npm.
      buildInputs = mkIf config.${row.flag} (optionals row.node [ pkgs.nodejs-slim ]);

    };

  };

}
