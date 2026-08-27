# The compiler that a plan's configure records. It writes the ghc arguments
# to `ghc-args.bin`, then stops at the first `--make`. This keeps a second
# way, such as profiling, from replacing the file. Other calls pass through.
#
# Example:
#
#   import ./ghc-shim.nix { inherit pkgs; ghc = hp.ghc; }
#   => <derivation ghc-shim> carrying bin/ghc
{ pkgs, ghc }:

pkgs.writeShellScriptBin "ghc" ''
  for argument in "$@"; do
    if [ "$argument" = --make ]; then
      for dumped in "$@"; do
        printf '%s\0' "$dumped"
      done > ghc-args.bin
      exit 1
    fi
  done

  exec ${ghc}/bin/${ghc.targetPrefix}ghc "$@"
''
