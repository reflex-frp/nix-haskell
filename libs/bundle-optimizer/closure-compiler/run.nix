# A linked `.jsexe` directory copied through with its `all.js` replaced by
# what closure-compiler makes of it. The rest of the directory stays as it
# was, so whatever loads the program keeps finding what it expects beside
# it.
#
# The linker writes `all.externs.js` next to the program, and the script
# always passes it, since under ADVANCED the compiler renames everything it
# is not told the runtime knows by name.
#
# Example:
#
#   import ./run.nix { inherit pkgs lib; } {
#     jsexe = "${frontend}/bin/frontend.jsexe";
#     enable = true;
#     level = "ADVANCED";
#     externs = [];
#     extraFlags = [ "--language_in UNSTABLE" "--warning_level QUIET" "--isolation_mode IIFE"
#                    "--assume_function_wrapper" "--emit_use_strict"
#                    "--jscomp_off=undefinedVars" ];
#   }
#   => <derivation frontend.jsexe-optimized>     # all.js compiled down;
#                                                # all.externs.js, rts.js,
#                                                # index.html and the rest as
#                                                # they were
#
#   import ./run.nix { inherit pkgs lib; } {
#     jsexe = "${frontend}/bin/frontend.jsexe";
#     enable = false;
#     level = "ADVANCED";
#     externs = [];
#     extraFlags = [];
#   }
#   => <derivation frontend.jsexe-unoptimized>   # the directory handed in, copied
#                                                # through, so a caller installs the
#                                                # same layout either way
{ pkgs, lib }:

with (import ../../common { inherit lib; });

{ jsexe, enable, level, externs, extraFlags }:

let name = artifact-name jsexe;

    flags = lib.concatStringsSep " " (
      [ "--compilation_level ${level}" ]
      ++ map (extern: "--externs ${extern}") externs
      ++ extraFlags);

in if ! enable
   then pkgs.runCommand "${name}-unoptimized" {} ''
     cp -r ${jsexe} $out
   ''
   else pkgs.runCommand "${name}-optimized" {
     nativeBuildInputs = [ pkgs.closurecompiler ];
   } ''
     cp -r ${jsexe} $out
     chmod -R u+w $out
     closure-compiler --externs $out/all.externs.js ${flags} \
       --js $out/all.js \
       --js_output_file $out/all.js.opt
     mv -f $out/all.js.opt $out/all.js
   ''
