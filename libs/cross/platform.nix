# What a cross platform name means. The names are `pkgs.pkgsCross`
# attribute names, the form the options keyed by platform expect. A name
# that denotes no platform is an error, not a silent non-match.
#
# Example:
#
#   platforms = import ./platform.nix { inherit lib; };
#   platforms.matches "wasi32" <an elaborated wasm32-wasi platform>  => true
#   platforms.keyFor [ "ghcjs" "wasi32" ] <elaborated wasm32-wasi>   => "wasi32"
#   platforms.keyFor [ "ghcjs" ] <elaborated wasm32-wasi>            => null
#   (platforms.targetFor "wasi32").isWasm                            => true
#   (platforms.targetFor "ghcjs").isGhcjs                            => true
#   platforms.probe pkgs   => { ghcjs = "ghcjs"; wasi32 = "wasi32"; ... }
{ lib }:

with lib;
with (import ../common { inherit lib; });

rec {

  targetFor = key:
    let prefix = message-prefix {};
        example = systems.examples.${key}
          or (throw (prefix ("\"${key}\" names neither the native system"
            + " nor a pkgsCross platform")));
    in systems.elaborate example;

  matches = key: targetPlatform:
    (targetFor key).config == targetPlatform.config;

  keyFor = keys: targetPlatform:
    findFirst (key: matches key targetPlatform) null keys;

  # `shell.crossPlatforms` selects from an attrset. This one maps every
  # `pkgsCross` platform name to itself, so a selection over it returns
  # the selected names.
  probe = pkgs: genAttrs (builtins.attrNames pkgs.pkgsCross) (name: name);

}
