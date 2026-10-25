{ system ? builtins.currentSystem
, inputs ? import ./inputs.nix { inherit system; }
, pkgs ? inputs.pkgs
}:

module:

let inputsWithPkgs = inputs // { inherit pkgs; };

    systemDefault = {
      config.system = pkgs.lib.mkDefault system;
    };

    argsFromConfig = { config, ... }: {
      _module.args.system = pkgs.lib.mkDefault config.system;
      _module.args.pkgs = pkgs.lib.mkDefault config.inputs.pkgs;
      # The project's own config, which a driver mirror replaces with the
      # enclosing project when it re-imports modules/common for itself.
      _module.args.topConfig = pkgs.lib.mkDefault config;
    };

    inputDefaults = { lib, ... }: {
      config.inputs = lib.mapAttrs (_: lib.mkDefault) inputsWithPkgs;
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

    specialArgs = {
      nix-haskell-libs = "${src}/libs";
      # A bare path: modules/inputs.nix imports ../inputs.nix, and the
      # filtered copy does not carry it.
      nix-haskell-modules = ./modules;
      nix-haskell-patches = "${src}/modules/patches";
      nix-haskell-compilers = "${src}/modules/compilers";
    };

    evalWith = definitions: pkgs.lib.evalModules {
      modules = [
        ./modules
        systemDefault
        argsFromConfig
        inputDefaults
      ] ++ pkgs.lib.toList module ++ definitions;

      inherit specialArgs;
    };

    overridesFor = options: diff:
      if pkgs.lib.isOption options
      then overrideOption options diff
      else pkgs.lib.mapAttrs (name: overridesFor options.${name}) diff;

    forcePriority = (pkgs.lib.mkForce null).priority;

    overlayable = prio: prio > forcePriority;

    overrideAbove = prio: value:
      pkgs.lib.mkIf (overlayable prio) (pkgs.lib.mkOverride (prio - 1) value);

    overrideOption = option: diff:
      if option.type.name == "submodule"
      then overridesFor option.valueMeta.configuration.options diff
      else if builtins.elem option.type.name [ "attrsOf" "lazyAttrsOf" ]
      then overrideEachKey option diff
      else overrideAbove option.highestPrio diff;

    overrideEachKey = option: diff:
      let prios = pkgs.lib.modules.mergeAttrDefinitionsWithPrio option;
          prioOf = name: prios.${name}.highestPrio or pkgs.lib.modules.defaultOverridePriority;
      in pkgs.lib.mapAttrs (name: overrideAbove (prioOf name)) diff;

    applyOverlay = pass: overlay:
      let diff = overlay result.config pass.evaluated.config;
          definitions = pass.definitions ++ [ { config = overridesFor pass.evaluated.options diff; } ];
      in {
        inherit definitions;
        evaluated = evalWith definitions;
      };

    plain = evalWith [];

    result = (builtins.foldl' applyOverlay { definitions = []; evaluated = plain; } plain.config.overlays).evaluated;

in result
