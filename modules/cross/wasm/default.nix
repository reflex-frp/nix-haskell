# Wasm target support.
#
# `isWasm` reports whether the project targets wasm, natively or through
# `shell.crossPlatforms`. When it is true, the shell gains Node.js, which
# Template Haskell needs.
#
# `wasm-optimize` turns a built wasm binary into what ships: wasm-opt and
# the strip that follows it, settled by the `wasm-opt` settings.
# `wasm-jsffi` reads out the JavaScript a wasm module cannot be
# instantiated without.

{ config, lib, pkgs, ... }:

with lib;
with (import ../../../libs/common { inherit lib; });

{

  imports = [
    (import ../../../libs/cross/target-module.nix "wasm")
  ];

  options.wasm-jsffi = function-option {
    default = { ghc, wasm }:
      import ../../../libs/cross/wasm-jsffi.nix { inherit pkgs lib; } { inherit ghc wasm; };
    defaultText = fenced-code ''<nix-haskell>/libs/cross/wasm-jsffi.nix'';
    description = ''
      The `ghc_wasm_jsffi.js` without which a GHC-built wasm module cannot
      be instantiated, read out of the binary by the compiler that built
      it:

      ```
      wasm-jsffi {
        ghc = config.<driver>.cross-compiler "wasi32";
        wasm = "''${frontend}/bin/frontend.wasm";
      }
      ```

      The compiler must be the one that produced the binary, and
      `<driver>.cross-compiler` names that compiler. Run this on the
      binary as linked, before `wasm-optimize` strips the sections it
      reads.
    '';
  };

}
