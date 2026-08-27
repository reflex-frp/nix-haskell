{ system ? builtins.currentSystem
, inputs ? {}
, pkgs ?
    if inputs ? nixpkgs
    then import inputs.nixpkgs { inherit system; }
    else import ./pins/nixpkgs { inherit system; }
}:

module:

let systemDefault = {
      config.system = pkgs.lib.mkDefault system;
    };

    argsFromConfig = { config, ... }: {
      _module.args.system = pkgs.lib.mkDefault config.system;
      _module.args.pkgs = pkgs.lib.mkDefault
        (import config.inputs.nixpkgs { inherit (config) system; });
      # The project's own config, which a driver mirror replaces with the
      # enclosing project when it re-imports modules/common for itself.
      _module.args.topConfig = pkgs.lib.mkDefault config;
    };

    inputDefaults = { lib, ... }: {
      config.inputs = lib.mapAttrs (_: lib.mkDefault) inputs;
    };

    # One store copy of the repository, filtered to libs/ and modules/.
    # The subpath arguments below share it, so a module imported through
    # them can reach libs/ with a relative import. A directory passed as
    # a bare path would be copied alone, and such an import would break.
    filterRoots = [ (toString ./libs) (toString ./modules) ];

    keep = path: _type:
      builtins.any
        (root: path == root || pkgs.lib.hasPrefix (root + "/") path)
        filterRoots;

    src = builtins.path { name = "nix-haskell-src"; path = ./.; filter = keep; };

in pkgs.lib.evalModules {
  modules = [
    ./modules
    systemDefault
    argsFromConfig
    inputDefaults
  ] ++ pkgs.lib.toList module;

  specialArgs = {
    nix-haskell-libs = "${src}/libs";
    # A bare path: modules/inputs.nix imports ../pins, and the filtered
    # copy does not carry pins/.
    nix-haskell-modules = ./modules;
    nix-haskell-patches = "${src}/modules/patches";
    nix-haskell-compilers = "${src}/modules/compilers";
  };
}
