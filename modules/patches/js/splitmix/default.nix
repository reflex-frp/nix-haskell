with (import ../../../../libs/common {});

patch-module {

  package = "splitmix";

  patches = [ ./splitmix-js.patch ];

  extras = [

    # splitmix's testu01 test-suite names the testu01 C library, which a
    # Haskell package set cannot resolve when splitmix is built from source.
    # The suite is behind a manual flag and never built.
    { config.nixpkgs.options.overrides = [
        (_: _: { testu01 = null; })
      ];
    }

  ];

}
