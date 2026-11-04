# Cross-compilation support: the per-target modules, and the functions
# both of them need.
#
# Each driver builds the per-target wrapper scripts
# (`wasm32-unknown-wasi ghc --version`) through `cross-wrappers`, with its
# own cross compilers.

{ config, lib, pkgs, ... }:

with lib;
with (import ../../libs/common { inherit lib; });

let crossPlatform = import ../../libs/cross/platform.nix { inherit lib; };

    selectedCrossPlatforms = config.shell.crossPlatforms (crossPlatform.probe pkgs);

in {

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
      default = import ../../libs/cross/native-ldflags-hook.nix { inherit pkgs lib; };
      defaultText = fenced-code ''<nix-haskell>/libs/cross/native-ldflags-hook.nix'';
      description = ''
        The shell hook run when `shell.crossPlatforms` selects targets.
        The call carries the selected `platforms` names. The default drops
        every selected target's `-L` paths from `NIX_LDFLAGS` and
        `NIX_LDFLAGS_FOR_TARGET`. The unfiltered values stay in the
        environment for the cross wrappers to start from.
      '';
      example = fenced-code ''{ platforms }: ""'';
    };

  };

  config = {

    # A shell with cross targets carries native and cross dependencies, and
    # each linker fails on the other side's objects. The hook keeps their
    # `-L` paths apart.
    shell.shellHook = mkIf (selectedCrossPlatforms != [])
      (config.native-ldflags-hook { platforms = selectedCrossPlatforms; });

  };

}
