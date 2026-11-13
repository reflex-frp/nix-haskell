# A haskell.nix module pointing a project's builds at the compiler's own C
# toolchain. The components of a cross project are built by the cross
# package set's stdenv, whose toolchain is not the one the compiler was
# configured with. A build step that needs C then looks in the wrong
# sysroot: `Setup configure`'s foreign-dependency checks fail on headers
# that are present, and what does compile targets a different ABI than the
# compiler's own libraries.
#
# The module goes into every project the driver builds, including the ones
# for the build platform, and decides per evaluation whether it applies.
# Only a platform with an entry of its own that carries a toolchain is
# affected.
#
# Example:
#
#   import ./compiler-toolchain.nix { inherit lib compilers; }
#   => a haskell.nix module which, in the project whose target has an entry of
#      its own carrying a wasi-sdk toolchain, gives every package of the project
#
#        configureFlags = [
#          "--with-gcc=/nix/store/...-wasi-sdk/bin/wasm32-wasi-clang"
#          "--with-ar=/nix/store/...-wasi-sdk/bin/llvm-ar"
#          "--with-ld=/nix/store/...-wasi-sdk/bin/wasm-ld"
#          "--with-strip=/nix/store/...-wasi-sdk/bin/llvm-strip"
#        ];
#
#      and in a project for a platform without an entry, or one whose entry
#      brings no toolchain, evaluates to nothing
{ lib, compilers }:

{ config, pkgs, ... }:

let key = compilers.targetKey pkgs.lib pkgs.stdenv.hostPlatform;

    compiler = compilers.resolve key;

    # `resolve` falls back to the compiler above the platform table, so only
    # the key says whether this platform has an entry of its own. Without
    # that check, a native toolchain would follow the build into every cross
    # target.
    ownToolchain = key != null && compiler.hasToolchain;

in {

  # This module must use mkIf, not a conditional body. `pkgs` reaches a
  # module through `_module.args`, so a module body that depends on `pkgs`
  # is a cycle.
  config = lib.mkIf ownToolchain {
    packages = lib.genAttrs config.package-keys (_: {
      configureFlags = compiler.toolchainFlags;
    });
  };

}
