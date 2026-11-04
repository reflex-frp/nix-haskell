{ lib, ... }:

with lib;
with (import ../libs/common { inherit lib; });

let overlay = mkOptionType {
      name = "overlay";
      description = "overlay function";
      check = isFunction;
      merge = mergeOneOption;
    };

in {

  options = {

    overlays = mkOption {
      type = types.listOf overlay;
      default = [];
      description = ''
        Overlays on the whole config, `final: prev:`, each returning
        option values to merge in. Each gets its own evaluation pass and
        lands one priority above the definition that won before it.
      '';
      example = fenced-code ''[ (final: prev: { inputs.pkgs = prev.inputs.pkgs.appendOverlays [ my-overlay ]; }) ]'';
    };

  };

}
