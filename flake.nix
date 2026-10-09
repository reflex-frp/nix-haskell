{
  inputs = {
    self.submodules = true;

    nixpkgs.url = ./pins/nixpkgs;
    haskell-nix.url = ./pins/haskell-nix;

    sandstone = {
      url = ./pins/sandstone;
      flake = false;
    };

    flake-compat.url = "github:NixOS/flake-compat";
  };

  outputs = inputs@{ self, ... }:
    let nixpkgs =
          if inputs ? "nixpkgs"
          then inputs.nixpkgs
          else builtins.getFlake "nixpkgs";

        eachSystem = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;

        pkgsFor = system: import nixpkgs { inherit system; };

        nix-haskellFor = system: import ./default.nix {
          inherit system inputs;
          pkgs = pkgsFor system;
        };
    in {
      lib = eachSystem (system:
        let nix-haskell = nix-haskellFor system;
            emptyProject = nix-haskell {};
            attrAsFunction = name: _: module: (nix-haskell module).${name};
        in {
          inherit nix-haskell;
        } // nixpkgs.lib.mapAttrs attrAsFunction emptyProject
      );

      packages = eachSystem (system:
        let project = (nix-haskellFor system) { src = ./.; };
        in {
          manual-view = project.manual.view;
          manual-md = project.manual.md;
          manual-man = project.manual.man;
        }
      );

      # The release set is a tree, which the flat `packages` cannot hold,
      # and its example matrix cross-compiles for every driver and compiler.
      # It therefore stays out of `checks`, which are the repo's own and
      # quick.
      legacyPackages = eachSystem (system: {
        release = import ./release.nix { inherit system inputs; };
      });

      checks = eachSystem (system:
        import ./tests {
          inherit system inputs;
          pkgs = pkgsFor system;
        }
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
