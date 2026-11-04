with (import ../../../../libs/common {});

patch-module {

  package = "jsaddle-wasm";

  patches = [ ./jsaddle-wasm-initialSyncDepth.patch ];

  extras = [

    # nixpkgs records the dependencies jsaddle-wasm's cabal file declares
    # for the build platform. The dependency it asks for only under wasm32
    # is therefore missing from the package database it is configured
    # against.
    ({ pkgs, ... }: {
      config.nixpkgs.options.overrides = [
        (self: super: {
          jsaddle-wasm = pkgs.haskell.lib.compose.addBuildDepend
            self.parser-regex super.jsaddle-wasm;
        })
      ];
    })

  ];

}
