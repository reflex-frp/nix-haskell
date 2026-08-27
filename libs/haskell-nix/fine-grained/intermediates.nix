# The plan of one package under the haskell.nix driver: a derivation whose
# output is a derivation. It configures the library as the component's own
# build does, then sandstone writes one derivation for each module and one
# that assembles them.
#
# Use `builtins.derivation`, not `stdenv.mkDerivation`. A builder-rpc-v0
# build gets no `$out`, and the stdenv setup stops without it.
#
# Example:
#
#   import ./intermediates.nix { inherit lib; } {
#     name = "frontend";
#     version = "0.1.0.0";
#     src = cleanSrc.root;
#     subdir = cleanSrc.subDir;
#     setup = "<default-setup>/bin/default-setup";
#     config-files = config.hsPkgs.makeConfigFiles { ... };
#     build-flags = [];
#     ghc = config.ghc.package;
#     shim = <ghc shim>;
#     tool = <sandstone>;
#     configure-flags = "lib:frontend --enable-shared";
#     inherit pkgs;
#   }
#   => <derivation frontend-0.1.0.0-intermediates.drv>
{ lib }:

{ name, version, src, subdir, setup, config-files, build-flags
, ghc, shim, tool, configure-flags, pkgs }:

let ghcCommand = "${ghc}/bin/${ghc.targetPrefix}ghc";

    # The database of `config-files` holds every dependency and boot
    # package, but it is a store path, and sandstone lifts only a database
    # outside the store, with its references scanned. That scan is what
    # gives each module derivation its dependencies, so the plan copies
    # the database out and drops the file's own `--package-db=` flags.
    prepare = pkgs.writeShellScript "fine-grained-plan-${name}" ''
      set -eu
      export PATH=${pkgs.coreutils}/bin:${ghc}/bin

      if [ ! -d "$src" ]; then
        echo "a fine-grained build needs a source directory, and got: $src" >&2
        exit 1
      fi

      cd "$NIX_BUILD_TOP"

      packageConfDir="$NIX_BUILD_TOP/package.conf.d"
      mkdir -p "$packageConfDir"
      cp -f "$configFiles/${config-files.packageCfgDir}/"*.conf "$packageConfDir/"
      ${ghcCommand}-pkg --package-db="$packageConfDir" recache

      cp -r --no-preserve=mode "$src" work
      cd "work${subdir}"

      install -m755 ${setup} Setup

      kept=
      for flag in $(cat "$configFiles/configure-flags"); do
        case "$flag" in
          --package-db=*) ;;
          *) kept="$kept $flag" ;;
        esac
      done

      ./Setup configure \
        --with-ghc=${shim}/bin/ghc \
        --with-ghc-pkg=${ghcCommand}-pkg \
        --package-db=clear \
        --package-db="$packageConfDir" \
        $kept \
        $planConfigureFlags

      # Without `sources`, sandstone uses the current directory as the
      # configured tree.
      exec ${tool}/bin/cabal-dyn-drv
    '';

in builtins.derivation ({
  # Sandstone names its derivation from this name. The name must end in
  # `.drv`, because the output is a derivation.
  name = "${name}-${version}-intermediates.drv";

  # This derivation and the ones it writes run where the build runs.
  system = pkgs.stdenv.buildPlatform.system;

  builder = "${prepare}";

  inherit src;
  configFiles = config-files.drv;
  planConfigureFlags = configure-flags;

  ghc = ghc.outPath;

  # The module derivations name these with placeholders. Send them as
  # derived paths, not as built outputs.
  bash = "${builtins.unsafeDiscardOutputDependency pkgs.bash.drvPath}!out";
  coreutils = "${builtins.unsafeDiscardOutputDependency pkgs.coreutils.drvPath}!out";
  lndir = "${builtins.unsafeDiscardOutputDependency pkgs.lndir.drvPath}!out";

  # Where the component's own build reads the tree that it restores.
  intermediatesSubdir = "share/haskell/${ghc.version}/${name}-${version}/dist";

  # Sandstone appends this to the `Setup build` whose ghc call the shim
  # captures, matching the component's own build target.
  buildTarget = "lib:${name}";

  requiredSystemFeatures = [ "builder-rpc-v0" ];

  __contentAddressed = true;
  outputHashMode = "text";
  outputHashAlgo = "sha256";
} // lib.optionalAttrs (build-flags != []) {
  buildFlags = lib.concatStringsSep " " build-flags;
})
