# The JavaScript side of a wasm program's JSFFI imports, read out of the
# binary by the `post-link.mjs` of the compiler that built it. A GHC-built
# wasm module cannot be instantiated without it. The file satisfies the
# module's `ghc_wasm_jsffi` import object.
#
# The compiler has to be the one that produced the binary, since
# post-link.mjs reads a custom section its own GHC wrote.
# `<driver>.cross-compiler` names that compiler, so a project does not have
# to know how a driver keeps them. Run this on the binary as linked. The
# optimizer's strip removes those sections.
#
# Example:
#
#   import ./wasm-jsffi.nix { inherit pkgs lib; } {
#     ghc = <wasm32-unknown-wasi-ghc-9.14.1>;
#     wasm = "${frontend}/bin/frontend.wasm";
#   }
#   => <derivation frontend.wasm-jsffi>   # an ES module of one export:
#                                         #   export default (__exports) => ({ ... })
{ pkgs, lib }:

with (import ../common { inherit lib; });

{ ghc, wasm }:

let name = artifact-name wasm;

# The libdir is asked for rather than assumed:
# - A version-named install keeps post-link.mjs under
#   lib/<prefix>ghc-<version>/lib.
# - A relocatable bindist keeps it directly under lib.
in pkgs.runCommand "${name}-jsffi" {
  nativeBuildInputs = [ pkgs.nodejs ];
} ''
  node $(${ghc}/bin/${ghc.targetPrefix}ghc --print-libdir)/post-link.mjs -i ${wasm} -o $out
''
