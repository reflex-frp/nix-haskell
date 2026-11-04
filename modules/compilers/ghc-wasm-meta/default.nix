# ghc-wasm-meta's wasm GHC as the compiler for a wasm target. A bindist
# carries none of the attributes the drivers read off a compiler, so this
# module supplies them, rather than every project that wants one. It also
# supplies the wasi-sdk the bindist was configured with, which everything
# built has to be pointed at.
#
# `flavour` is the GHC series to take from the pin. Pass `version` for a
# nightly, whose derivation name carries only that series. Both drivers
# work either way. The builds that cannot use the bindist itself (a package
# set to solve against, the shell's tools) follow the version, so a full
# version keeps those on the release it came from.
#
# Example:
#
#   { nix-haskell-compilers, ... }:
#   {
#     imports = [
#       (import "${nix-haskell-compilers}/ghc-wasm-meta" {
#         flavour = "9.12";
#         version = "9.12.4.20260731";
#       })
#     ];
#   }
{ platform ? "wasi32", flavour, version ? null, drivers ? null }:

{ config, lib, pkgs, ... }:

with (import ../../../libs/common { inherit lib; });

let src = config.inputs.ghc-wasm-meta;

    # shortcut: a ghc-wasm-meta 9.14 bindist reports a `ghc-internal Unit Id`
    # that its own database lacks, and cabal 3.18 rejects that. Drop this
    # once the bindist's `--info` matches its database.
    fixInfo = ''
      if internal=$($out/bin/wasm32-wasi-ghc-pkg field ghc-internal id --global --simple-output 2>/dev/null); then
        for ghc in $out/bin/wasm32-wasi-ghc $out/bin/wasm32-wasi-ghc-9.*; do
          unfixed=$out/bin/.$(basename $ghc)-unfixed-info
          mv $ghc $unfixed
          cat > $ghc <<EOF
      #!${pkgs.runtimeShell}
      for arg in "\$@"; do
        if [ "\$arg" = --info ]; then
          $unfixed "\$@" | ${pkgs.gnused}/bin/sed 's|("ghc-internal Unit Id","[^"]*")|("ghc-internal Unit Id","'$internal'")|'
          exit "\''${PIPESTATUS[0]}"
        fi
      done
      exec $unfixed "\$@"
      EOF
          chmod +x $ghc
        done
      fi
    '';

    ghc = (pkgs.callPackage "${src}/${paths.ghc-wasm-meta.wasm32-wasi-ghc}" { inherit flavour; }).overrideAttrs (old: {
      postInstall = old.postInstall + fixInfo;
    });

    sdk = pkgs.callPackage "${src}/${paths.ghc-wasm-meta.wasi-sdk}" {};

    compiler = {
      platforms.${platform} = {
        package = ghc;
        inherit version;
        targetPrefix = "wasm32-wasi-";

        # The wasm backend's Template Haskell interpreter loads shared
        # objects.
        enableShared = true;

        # The bindist keeps its package database and settings directly
        # under lib, not under the lib/<prefix>ghc-<version>/lib of a
        # version-named install.
        haskell-nix.libDir = "lib";

        # The bindist's `text` needs `system-cxx-std-lib`, the C++ runtime
        # of the simdutf it uses.
        haskell-nix.extraNonReinstallablePkgs = [ "system-cxx-std-lib" ];

        # The wasm backend runs Template Haskell itself, so splices must
        # not be proxied to the target, which has no sockets to proxy over.
        nixpkgs.enableExternalInterpreter = false;

        toolchain = {
          package = sdk;
          # The names the sdk's own setup hook exports as CC, AR, LD and
          # STRIP.
          cc = "wasm32-wasi-clang";
          ar = "llvm-ar";
          ld = "wasm-ld";
          strip = "llvm-strip";
        };
      };
    };

in {

  config = under drivers { inherit compiler; };

}
