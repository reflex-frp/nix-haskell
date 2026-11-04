# The shared helpers of libs/, as one attribute set.
#
# Example:
#
#   with (import ./prelude { inherit lib; });
#
#   and [ true false ]
#   => false
{ lib ? null }:

{
  and = import ./and.nix { inherit lib; };

  artifact-name = import ./artifact-name.nix { inherit lib; };

  fenced-code = import ./fenced-code.nix { inherit lib; };

  function-option = import ./function-option.nix { inherit lib; };

  is-set = import ./is-set.nix { inherit lib; };

  is-settable = import ./is-settable.nix { inherit lib; };

  is-visible = import ./is-visible.nix { inherit lib; };

  link-farm-entries = import ./link-farm-entries.nix { inherit lib; };

  recurse-for-derivations = import ./recurse-for-derivations.nix { inherit lib; };

  submodule-type = import ./submodule-type.nix;

  under = import ./under.nix;
}
