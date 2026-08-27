# Every Haskell package a package builds against, transitively: its own
# stated dependencies, then the library run dependencies of those, and so
# on. A plan's database needs them all. A database entry names its own
# dependencies by id, and Cabal refuses a database with an entry it
# cannot chase to the end.
#
# A dependency's test and benchmark dependencies stay out, as does any
# package without cabal2nix's `getCabalDeps` record, the compiler above
# all: its database directory holds every boot conf, whose relative
# paths break when copied. A dependency the walk misses fails configure
# loudly.
#
# Example:
#
#   import ./haskell-dependency-closure.nix { inherit lib; } hp.reflex-todomvc
#   => [ <derivation reflex-dom-0.6.3.4> <derivation reflex-0.9.4.0> ... ]
{ lib }:

package:

let direct = import ./haskell-dependencies.nix { inherit lib; };

    recorded = dependency: dependency ? getCabalDeps;

    # What a consumer of the library needs, transitively.
    libraryDependencies = dependency:
      lib.filter (d: d != null)
        ((dependency.getCabalDeps.buildDepends or [])
         ++ (dependency.getCabalDeps.libraryHaskellDepends or []));

    entry = dependency: {
      key = dependency.outPath;
      value = dependency;
    };

in map (item: item.value)
     (builtins.genericClosure {
       startSet = map entry (lib.filter recorded (direct package));
       operator = item: map entry (lib.filter recorded (libraryDependencies item.value));
     })
