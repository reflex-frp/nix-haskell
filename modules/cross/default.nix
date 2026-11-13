# Cross-compilation support: the per-target modules, and the functions
# both of them need.
#
# Each driver builds these from its own cross compilers:
# - the per-target wrapper scripts (`wasm32-unknown-wasi ghc --version`),
#   through `cross-wrappers`
# - the shell hook that keeps native and cross link flags apart, through
#   `native-ldflags-hook`

{ lib, ... }:

with lib;
with (import ../../libs/common { inherit lib; });

{

  imports = [
    ./ghcjs
    ./wasm
  ];

  options = {

    cross-targets = mkOption {
      type = types.attrsOf types.raw;
      internal = true;
      default = {};
      description = ''
        The registered cross-target rows, keyed by target name. Each
        imported cross-target module adds its row. The bundle fields'
        dispatch reads them. Two rows for one name are a definition
        conflict.
      '';
    };

    cross-wrappers = function-option {
      result = types.listOf types.package;
      default = { ghc, pkgs }:
        import ../../libs/cross/wrappers.nix { inherit pkgs lib; } ghc;
      defaultText = fenced-code ''<nix-haskell>/libs/cross/wrappers.nix'';
      description = ''
        The wrapper scripts a shell gets for one cross compiler. Each is
        a `<target-prefix>` dispatcher that runs the compiler's tools with
        the native link flags filtered away. The call carries:

        - `ghc`, the cross compiler
        - `pkgs`, what the scripts are built with

        The default returns no script for a compiler without a target
        prefix.
      '';
      example = fenced-code ''{ ghc, pkgs }: []'';
    };

    native-ldflags-hook = function-option {
      result = types.lines;
      default = import ../../libs/cross/native-ldflags-hook.nix { inherit lib; };
      defaultText = fenced-code ''<nix-haskell>/libs/cross/native-ldflags-hook.nix'';
      description = ''
        The shell hook that keeps native and cross link flags apart. Each
        driver calls it with `ghcs`, the cross compilers of the platforms
        `shell.crossPlatforms` selects. The default drops every `-L` path
        that names one of their target prefixes from `NIX_LDFLAGS` and
        `NIX_LDFLAGS_FOR_TARGET`. It writes nothing when no compiler has a
        prefix. The unfiltered values stay in the environment for the cross
        wrappers to start from.
      '';
      example = fenced-code ''{ ghcs }: ""'';
    };

  };

}
