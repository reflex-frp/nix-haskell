# The generated driver stages, under `haskell-nix.stages`:
#
# - the project source with its appended stanzas
# - the source-repository-package pins
# - the hackage index for the overlaid packages
#
# Each stage is an option, so a project can replace one stage's value and
# keep the others generated.
{ lib, pkgs, config, cfg, srpStanzaLines }:

with lib;
with (import ../../libs/common { inherit lib; });

let srpDriver = (import ../../libs/cabal.nix { inherit pkgs; }).source-repository-packages cfg.source-repository-packages;

    hackageDriver = import ../../libs/haskell-nix/hackage-driver.nix {
      pkgs = config."haskell-nix".nixpkgs;
      modules = cfg.hackage-overlays;
    };

in {

  stages = {

    # ------------------------------------------------------------------------
    # Source
    # ------------------------------------------------------------------------

    src = mkOption {
      type = types.path;
      default = import ../../libs/haskell-nix/src-driver.nix {
        inherit pkgs;
        src = cfg.src-cleaned;
        extraCabalProject = srpStanzaLines ++ cfg.extraCabalProject;
      };
      defaultText = fenced-code ''<nix-haskell>/libs/haskell-nix/src-driver.nix'';
      description = ''
        `src-cleaned`, with the `extraCabalProject` lines and the
        generated `source-repository-package` stanzas appended to its
        `cabal.project`. The driver builds the project from this.
      '';
    };

    # ------------------------------------------------------------------------
    # Stanzas and pins
    # ------------------------------------------------------------------------

    source-repository-packages = mkOption {
      type = types.submodule {
        options = {

          inputMap = mkOption {
            type = types.attrsOf types.attrs;
            default = srpDriver.inputMap;
            defaultText = fenced-code ''inputMap from <nix-haskell>/libs/cabal.nix source-repository-packages'';
            description = ''
              Pins each generated stanza's `location` to its fetched
              source.
            '';
            example = fenced-code ''{ "https://github.com/reflex-frp/reflex-dom" = { outPath = ./deps/reflex-dom; rev = "HEAD"; }; }'';
          };

          cabalProject = mkOption {
            type = types.listOf types.str;
            default = srpDriver.cabalProject;
            defaultText = fenced-code ''cabalProject from <nix-haskell>/libs/cabal.nix source-repository-packages'';
            description = ''
              The generated `source-repository-package` stanzas, as
              cabal.project lines to append.
            '';
            example = fenced-code ''
              [ '''
                source-repository-package
                  type: git
                  location: https://github.com/reflex-frp/reflex-dom
                  tag: HEAD
              ''' ]
            '';
          };

        };
      };
      default = {};
      description = ''
        `source-repository-package` stanzas and the `inputMap` entries
        that pin their sources, generated from the common
        `source-repository-packages`.
      '';
    };

    # ------------------------------------------------------------------------
    # Hackage index
    # ------------------------------------------------------------------------

    hackage = mkOption {
      type = types.submodule {
        options = {

          extra-hackage-tarballs = mkOption {
            type = types.attrsOf types.package;
            default = hackageDriver.extra-hackage-tarballs;
            defaultText = fenced-code ''extra-hackage-tarballs from <nix-haskell>/libs/haskell-nix/hackage-driver.nix'';
            description = ''
              The generated hackage index tarballs, keyed by repository
              name.
            '';
          };

          extra-hackages = mkOption {
            type = types.listOf types.attrs;
            default = hackageDriver.extra-hackages;
            defaultText = fenced-code ''extra-hackages from <nix-haskell>/libs/haskell-nix/hackage-driver.nix'';
            description = ''
              The imported hackage expressions the cabal solver reads
              beside the real index. haskell.nix merges each one over its
              hackage set.
            '';
          };

          package-overlays = mkOption {
            type = types.listOf types.deferredModule;
            default = hackageDriver.package-overlays;
            defaultText = fenced-code ''package-overlays from <nix-haskell>/libs/haskell-nix/hackage-driver.nix'';
            description = ''
              Project modules that force each overlaid package's `src` to
              its local source.
            '';
            example = fenced-code ''[ { packages.reflex-dom.src = lib.mkForce ./deps/reflex-dom; } ]'';
          };

        };
      };
      default = {};
      description = ''
        A generated hackage index that makes `hackage-overlays` visible to
        the cabal solver.
      '';
    };

  };

}
