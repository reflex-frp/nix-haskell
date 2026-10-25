{ config, lib, ... }:

with lib;
with (import ../libs/prelude { inherit lib; });

let thunkSource = import ../libs/thunk.nix;

    isSource = value: builtins.isPath value || builtins.isString value || value ? outPath;

    resolve = value:
      if isSource value
      then thunkSource value
      else value;

    withMatchingPkgs = inputs: inputs // {
      pkgs = import ../libs/nixpkgs/reimport.nix inputs.pkgs {
        inherit (config) system;
        path = inputs.nixpkgs;
      };
    };

in {

  options = {

    inputs = mkOption {
      type = types.attrsOf types.raw;
      apply = inputs: withMatchingPkgs (mapAttrs (_: resolve) inputs);
      default = {};
      description = ''
        Sources of dependencies, keyed the way flake inputs are. An entry
        accepts whatever a flake input can be: a flake input, a store path,
        a checkout, or a packed thunk. Entries missing here fall back to
        nix-haskell's own `inputs.nix`. An entry that is not a source, such as the `pkgs`
        package set, passes through unchanged.
      '';
      example = fenced-code ''{ ghc-wasm-meta = ./deps/ghc-wasm-meta; }'';
    };

  };

  config = {

    inputs = mapAttrs (_: mkOptionDefault) (import ../inputs.nix { inherit (config) system; });

  };

}
