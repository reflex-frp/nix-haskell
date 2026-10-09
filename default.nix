{ system ? builtins.currentSystem
, inputs ? import ./inputs.nix
, pkgs ?
    if inputs ? nixpkgs
    then import inputs.nixpkgs { inherit system; }
    else import ./pins/nixpkgs { inherit system; }
}:

with pkgs.lib;

module:

let eval = import ./eval.nix { inherit system pkgs inputs; };

    evaluated = eval module;
    config = evaluated.config;

    docs = import ./docs.nix {
      inherit pkgs;
      options = evaluated.options;
    };

    mkProject = driver: x:
      let xs = toList x;
          evaled = eval xs;
      in {
        config = evaled.config;
        override = y: mkProject driver (xs ++ toList y);
      } // evaled.config.${driver}.project;

    syntheticSrc = packages: pkgs.writeTextFile {
      name = "ghc-with-packages-src";
      destination = "/ghc-with-packages.cabal";
      text = ''
        cabal-version: 2.4
        name: ghc-with-packages
        version: 0

        library
          build-depends: ${builtins.concatStringsSep ", " packages}
      '';
    };

    drivers = {

      haskell-nix = {
        project = mkProject "haskell-nix" module;

        ghcWithPackages = m: packages:
          let syntheticModule = {
                name = "ghc-with-packages";
                src = syntheticSrc packages;
                haskell-nix.options.cabalProjectLocal = ''
                  extra-packages: ${builtins.concatStringsSep ", " packages}
                '';
              };
              proj = mkProject "haskell-nix" ([ syntheticModule ] ++ toList m);
              installPlan = proj.pkg-set.config.plan-json.install-plan;
              preExistingPkgs = filter (p: p.type == "pre-existing") installPlan;
              preExistingPkgsNames = map (p: p.pkg-name) preExistingPkgs;
              wanted = filter (n: !(elem n preExistingPkgsNames)) packages;
          in proj.ghcWithPackages (ps: map (n: ps.${n}) wanted);
      };

      nixpkgs = {
        project = mkProject "nixpkgs" module;

        ghcWithPackages = m: packages:
          let syntheticModule = {
                name = "ghc-with-packages";
                src = syntheticSrc packages;
              };
              proj = mkProject "nixpkgs" ([ syntheticModule ] ++ toList m);
              resolve = ps: n: ps.${n} or (throw "ghcWithPackages: unknown package ${n}");
              # boot libraries are null in the set and must not reach the wrapper
              selected = ps: filter (p: p != null) (map (resolve ps) packages);
          in proj.haskellPackages.ghcWithPackages selected;
      };

    };

    projects = mapAttrs (_: driver: driver.project) drivers;

    withPackages = mapAttrs (_: driver: driver.ghcWithPackages) drivers;

in {
  inherit config;

  pkgs = evaluated._module.args.pkgs;

  manual = docs;
} // drivers
  // {
    project = projects;
    ghcWithPackages = withPackages;
  }
