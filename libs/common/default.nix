# The shared helpers of libs/ and the files nix-haskell imports from its
# inputs, as one attribute set.
#
# Example:
#
#   with (import ./common { inherit lib; });
#
#   and [ true false ]
#   => false
#
#   paths.haskell-nix.host-map
#   => "lib/host-map.nix"
{ lib ? null }:

import ../prelude { inherit lib; } // {
  build-phases = import ./build-phases.nix { inherit lib; };
  local-packages-selection = import ./local-packages-selection.nix;
  message-prefix = import ./message-prefix.nix;
  patch-module = import ./patch-module.nix;
  paths = import ./upstream-paths.nix;
  thunk = import ../thunk.nix;
  thunks = import ../thunks.nix;
}
