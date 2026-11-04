# A haskell.nix module applying one platform's package customization. The
# driver builds a project per cross target from the same modules, so the module
# decides per evaluation which platform it is in and applies that entry, if
# there is one.
#
# `fields` are the per-package fields whose names are haskell.nix's own, so
# they can be written through verbatim. `src` is not among them. It replaces
# a value haskell.nix already has, so it is forced.
#
# Example:
#
#   import ./platform-packages.nix {
#     inherit lib fields;
#     platforms = { wasi32.packages.reflex-dom.flags.use-warp = false; };
#   }
#   => a haskell.nix module which, in the project whose target is wasm32-wasi,
#      evaluates to
#
#        config.packages.reflex-dom.flags.use-warp = false;
#
#      and in every other project, and in one where reflex-dom is not a package
#      of the project at all, to nothing
{ lib, platforms, fields }:

{ config, pkgs, ... }:

with lib;
with (import ../common { inherit lib; });

let crossPlatform = import ../cross/platform.nix { inherit lib; };

    key = crossPlatform.keyFor (attrNames platforms) pkgs.stdenv.hostPlatform;

    tweaks = if key == null then {} else platforms.${key}.packages;

    # A field the project left alone carries the option's own empty value.
    # Writing it through would turn that empty value into a definition.
    translate = packageTweaks:
      let written = filter (field: is-set packageTweaks.${field}) fields;
      in listToAttrs (map (field: nameValuePair field packageTweaks.${field}) written)
        // optionalAttrs (is-set packageTweaks.src) { src = mkForce packageTweaks.src; };

in {

  # A package absent from this project is skipped.
  config = mkIf (key != null) {
    packages = mapAttrs (_: translate)
      (filterAttrs (name: _: config.packages ? ${name}) tweaks);
  };

}
