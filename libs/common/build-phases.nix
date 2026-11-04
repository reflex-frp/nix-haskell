# The cabal build phases whose pre and post hooks a package can carry:
# - `names` are the phases, in build order.
# - `hooks` are the fourteen pre/post hook names derived from them.
#
# Example:
#
#   buildPhases = import ./build-phases.nix { inherit lib; };
#
#   buildPhases.names
#   => [ "Unpack" "Patch" "Configure" "Build" "Check" "Haddock" "Install" ]
#
#   buildPhases.hooks
#   => [ "preUnpack" "postUnpack" "prePatch" "postPatch" "preConfigure"
#        "postConfigure" "preBuild" "postBuild" "preCheck" "postCheck"
#        "preHaddock" "postHaddock" "preInstall" "postInstall" ]
{ lib }:

let names = [ "Unpack" "Patch" "Configure" "Build" "Check" "Haddock" "Install" ];

in {
  inherit names;

  hooks = lib.concatMap (phase: [ "pre${phase}" "post${phase}" ]) names;
}
