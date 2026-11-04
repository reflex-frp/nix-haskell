# A patch module: the given patches keyed under the selected drivers, plus
# any driver-specific extra modules. The result takes `drivers` the way
# every patch module does: null applies the patch to all drivers. The
# patch entry is ignored when the project does not contain the package.
#
# Example:
#
#   import ./patch-module.nix {
#     package = "splitmix";
#     patches = [ ./splitmix-js.patch ];
#   } { drivers = [ "haskell-nix" ]; }
#   => a module setting `haskell-nix.packages.splitmix.patches`
with (import ../prelude {});

{ package, patches, extras ? [] }:

{ drivers ? null }:

{
  imports = [
    { config = under drivers { packages.${package}.patches = patches; }; }
  ] ++ extras;
}
