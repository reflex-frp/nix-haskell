# The prefix of every message nix-haskell throws or warns. `driver` names
# the driver when the site knows which one is running.
#
# Example:
#
#   (import ./message-prefix.nix { driver = "nixpkgs"; }) "no cabal package in ./x"
#   => "nix-haskell (nixpkgs driver): no cabal package in ./x"
#
#   (import ./message-prefix.nix {}) "unknown platform"
#   => "nix-haskell: unknown platform"
{ driver ? null }:

message:

let tag =
      if driver == null
      then ""
      else " (${driver} driver)";

in "nix-haskell${tag}: ${message}"
