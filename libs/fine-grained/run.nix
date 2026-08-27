# A Nix that runs fine-grained builds on a machine whose daemon cannot:
# it drives a store of its own with the experimental features and the
# `builder-rpc-v0` system feature on, and the machine's store fills that
# one by copy.
#
# `NIX_DYNAMIC_DRV_STORE` names the store. Unset, it is `.nix/store`
# under the project root: the first directory from `$PWD` upward that
# holds `.nix`, `cabal.project`, or `.git`, so a previous run's `.nix`
# pins the root. With none up to `/`, it is `$PWD` itself.
#
# A machine's configuration names paths that only its daemon reads, its
# binfmt registrations and its signing key among them, so the script
# starts from the Nix defaults.
#
# Example:
#
#   import ./run.nix { inherit pkgs; nix = config.fine-grained.nix; }
#   => <derivation fine-grained-nix> carrying bin/fine-grained-nix
{ pkgs, nix }:

pkgs.writeShellScriptBin "fine-grained-nix" ''
  root=$PWD
  until [ -e "$root/.nix" ] || [ -e "$root/cabal.project" ] || [ -e "$root/.git" ]; do
    root=''${root%/*}
    if [ -z "$root" ]; then
      root=$PWD
      break
    fi
  done

  export NIX_CONF_DIR=${pkgs.emptyDirectory}
  export NIX_USER_CONF_FILES=

  exec ${nix}/bin/nix \
    --store "''${NIX_DYNAMIC_DRV_STORE:-$root/.nix/store}" \
    --substituters 'daemon?trusted=1 https://cache.nixos.org' \
    --extra-experimental-features 'nix-command ca-derivations dynamic-derivations' \
    --extra-system-features builder-rpc-v0 \
    "$@"
''
