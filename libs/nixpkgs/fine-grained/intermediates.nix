# The plan of one package: a derivation whose output is a derivation. It
# configures the package as the package's own build does, then sandstone
# writes one derivation for each module and one that assembles them.
#
# Use `builtins.derivation`, not `stdenv.mkDerivation`. A builder-rpc-v0
# build gets no `$out`, and the stdenv setup stops without it.
#
# Example:
#
#   import ./intermediates.nix { inherit lib; } {
#     name = "frontend";
#     package = hp.frontend;
#     dependencies = [ hp.reflex ];
#     ghc = hp.ghc;
#     shim = <ghc shim>;
#     tool = <sandstone>;
#     configure-flags = "--enable-shared";
#     inherit pkgs;
#   }
#   => <derivation frontend-0.1-intermediates.drv>
{ lib }:

{ name, package, dependencies, ghc, shim, tool, configure-flags, pkgs }:

let ghcCommand = "${ghc}/bin/${ghc.targetPrefix}ghc";

    # Keep the database outside the store. Cabal writes its path into the ghc
    # arguments, and sandstone then moves it into the store and scans it for
    # references. This gives each module derivation its dependencies.
    prepare = pkgs.writeShellScript "fine-grained-plan-${name}" ''
      set -eu
      export PATH=${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${ghc}/bin

      if [ ! -d "$src" ]; then
        echo "a fine-grained build needs a source directory, and got: $src" >&2
        exit 1
      fi

      cd "$NIX_BUILD_TOP"

      packageConfDir="$NIX_BUILD_TOP/package.conf.d"
      mkdir -p "$packageConfDir"
      for dependency in $dependencies; do
        for database in $(find "$dependency/lib" -maxdepth 3 -type d -name package.conf.d 2>/dev/null); do
          cp -f "$database/"*.conf "$packageConfDir/"
        done
      done
      ${ghcCommand}-pkg --package-db="$packageConfDir" recache

      cp -r --no-preserve=mode "$src" work
      cd work

      if [ ! -e Setup.hs ] && [ ! -e Setup.lhs ]; then
        echo 'import Distribution.Simple' > Setup.hs
        echo 'main = defaultMain' >> Setup.hs
      fi
      ${ghcCommand} --make -o Setup Setup.hs

      ./Setup configure \
        --with-ghc=${shim}/bin/ghc \
        --with-ghc-pkg=${ghcCommand}-pkg \
        --package-db="$packageConfDir" \
        $planConfigureFlags

      # Without `sources`, sandstone uses the current directory as the
      # configured tree.
      exec ${tool}/bin/cabal-dyn-drv
    '';

in builtins.derivation {
  # Sandstone names its derivation from this name. The name must end in
  # `.drv`, because the output is a derivation.
  name = "${name}-${package.version}-intermediates.drv";

  # This derivation and the ones it writes run where the build runs, not
  # where a cross set's packages run.
  system = pkgs.stdenv.buildPlatform.system;

  builder = "${prepare}";

  src = package.src;
  inherit dependencies;
  planConfigureFlags = configure-flags;

  ghc = ghc.outPath;

  # The module derivations name these with placeholders. Send them as
  # derived paths, not as built outputs.
  bash = "${builtins.unsafeDiscardOutputDependency pkgs.bash.drvPath}!out";
  coreutils = "${builtins.unsafeDiscardOutputDependency pkgs.coreutils.drvPath}!out";
  lndir = "${builtins.unsafeDiscardOutputDependency pkgs.lndir.drvPath}!out";

  # Where the package's own build reads the tree that it restores.
  intermediatesSubdir = "share/haskell/${ghc.version}/${package.pname}-${package.version}/dist";

  requiredSystemFeatures = [ "builder-rpc-v0" ];

  __contentAddressed = true;
  outputHashMode = "text";
  outputHashAlgo = "sha256";
}
