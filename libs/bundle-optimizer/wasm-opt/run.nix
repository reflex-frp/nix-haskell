# A wasm binary put through wasm-opt and then stripped of its custom
# sections. Nothing reads those sections once the JSFFI bindings have been
# read out of them, so run the JSFFI read on the binary as linked, before
# this. The output is the file itself rather than a directory holding it,
# so a caller installs it under whatever name it wants.
#
# Example:
#
#   import ./run.nix { inherit pkgs lib; } {
#     wasm = "${frontend}/bin/frontend.wasm";
#     enable = true;
#     level = "2";
#     extraFlags = [ "-ol 2" "-s 1" "--low-memory-unused" "--strip-dwarf" "--converge" ];
#   }
#   => <derivation frontend.wasm-optimized>     # the optimized binary, the file
#                                              # itself rather than a directory
#
#   import ./run.nix { inherit pkgs lib; } {
#     wasm = "${frontend}/bin/frontend.wasm";
#     enable = false;
#     level = "2";
#     extraFlags = [];
#   }
#   => <derivation frontend.wasm-unoptimized>   # the file handed in, copied
#                                              # through, so a caller installs
#                                              # the same path either way
{ pkgs, lib }:

with (import ../../common { inherit lib; });

{ wasm, enable, level, extraFlags }:

let name = artifact-name wasm;

    flags = lib.concatStringsSep " " ([ "-all" "-O${level}" ] ++ extraFlags);

in if ! enable
   then pkgs.runCommand "${name}-unoptimized" {} ''
     cp ${wasm} $out
   ''
   else pkgs.runCommand "${name}-optimized" {
     nativeBuildInputs = [ pkgs.binaryen pkgs.wasm-tools ];
   } ''
     wasm-opt ${flags} ${wasm} -o optimized.wasm
     wasm-tools strip -a optimized.wasm -o $out
   ''
