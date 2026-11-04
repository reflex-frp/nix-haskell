# A hoogle over the documentation of a ghc environment's packages.
#
# Example:
#
#   import ./hoogle-index.nix { inherit pkgs; } { ghc = project.shell.ghc; }
#   => <derivation hoogle-index>, whose bin/hoogle searches that documentation
{ pkgs }:

{ ghc }:

let hoogle = pkgs.buildPackages.haskellPackages.hoogle;

in pkgs.buildPackages.runCommand "hoogle-index" {} ''
  database=$out/share/doc/hoogle/default.hoo
  mkdir -p $out/bin $out/share/doc/hoogle

  sources=()
  for dir in $(${ghc}/bin/ghc-pkg field '*' haddock-html --simple-output --expand-pkgroot); do
    if [ -d "$dir" ]; then
      sources+=("--local=$dir")
    fi
  done
  ${hoogle}/bin/hoogle generate --database "$database" "''${sources[@]}"

  cat > $out/bin/hoogle <<EOF
  #!${pkgs.buildPackages.runtimeShell}
  command=\$1
  shift
  exec ${hoogle}/bin/hoogle "\$command" --database $database "\$@"
  EOF
  chmod +x $out/bin/hoogle
''
