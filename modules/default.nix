{ ... }:

{

  imports = [
    ./common

    # Drivers
    ./haskell.nix
    ./nixpkgs

    ./cross

    ./inputs.nix
    ./optimizations.nix
    ./overlays.nix
  ];

}
