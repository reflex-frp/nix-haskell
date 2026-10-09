{
  inputs = {
    self.submodules = true;

    nix-haskell.url = ../..;

    nixpkgs.follows = "nix-haskell/nixpkgs";
  };

  outputs = inputs@{ self, ... }:
    let nixpkgs =
          if inputs ? "nixpkgs"
          then inputs.nixpkgs
          else builtins.getFlake "nixpkgs";

        eachSystem = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;

        projectFor = system: import ./default.nix { inherit system inputs; };

        todomvcExe = crossProject:
          crossProject.hsPkgs.reflex-todomvc.components.exes.reflex-todomvc;
    in {
      legacyPackages = eachSystem (system:
        projectFor system // {
          # Every driver, compiler and cross target this example is meant
          # to work for, built both ways.
          release = import ./release.nix { inherit system inputs; };
        }
      );

      packages = eachSystem (system:
        let project = projectFor system;
        in rec {
          default = haskell-nix;
          haskell-nix = todomvcExe project.haskell-nix.projectCross.wasi32;
          nixpkgs = project.nixpkgs.projectCross.ghcjs.packages.reflex-todomvc;

          # Builds the wasm target with the GHC 9.12 bindist from the
          # ghc-wasm-meta pin instead of the drivers' own compilers.
          haskell-nix-wasm-meta = todomvcExe project.haskell-nix-wasm-meta.projectCross.wasi32;
          nixpkgs-wasm-meta = project.nixpkgs-wasm-meta.projectCross.wasi32.packages.reflex-todomvc;
        });

      devShells = eachSystem (system:
        let shells = import ./shell.nix { inherit system inputs; };
        in shells // { default = shells.haskell-nix; }
      );
    };

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nixcache.reflex-frp.org"
      "https://cache.iog.io"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "ryantrinkle.com-1:JJiAKaRv9mWgpVAz8dwewnZe0AzzEAzPkagE9SP5NWI=" # reflex-frp
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
    ];
    allow-import-from-derivation = "true";
  };
}
