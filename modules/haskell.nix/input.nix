# Where haskell.nix comes from: the checkout, the nixpkgs it pins, the
# arguments that nixpkgs is imported with, and the helpers the overlay
# puts into the resulting package set.
{ lib, config, system }:

with lib;
with (import ../../libs/common { inherit lib; });

let haskellNixArgs = config."haskell-nix".input.nixpkgsArgs;

in {

  input = mkOption {
    type = types.raw;
    default = import config.inputs."haskell-nix" { inherit system; };
    defaultText = fenced-code ''import config.inputs."haskell-nix" { inherit system; }'';
    description = ''
      The haskell.nix checkout this driver builds with, imported for
      `system`. The driver takes everything else out of it: the nixpkgs
      it pins, the overlay that builds a project, and the helpers for
      selecting components.
    '';
  };

  nixpkgsSource = mkOption {
    type = types.raw;
    default = config."haskell-nix".input.sources.nixpkgs-unstable;
    defaultText = fenced-code ''config."haskell-nix".input.sources.nixpkgs-unstable'';
    description = ''
      The nixpkgs this driver builds from: the one haskell.nix pins, not
      the project's `inputs.nixpkgs`. haskell.nix's overlays and its
      compilers are written against that revision. The nixpkgs driver
      follows the project's pin instead.
    '';
  };

  nixpkgsArgs = mkOption {
    type = types.raw;
    default = haskellNixArgs // {
      overlays = haskellNixArgs.overlays ++ config.inputs.pkgs.overlays;
    };
    defaultText = fenced-code ''
      config."haskell-nix".input.nixpkgsArgs // {
        overlays = config."haskell-nix".input.nixpkgsArgs.overlays ++ config.inputs.pkgs.overlays;
      }
    '';
    description = ''
      The arguments the driver imports nixpkgs with: haskell.nix's own
      overlays, which put `haskell-nix` into the package set, then the
      overlays of `inputs.pkgs`, and the configuration its compilers are
      built under.
    '';
  };

  nixpkgs = mkOption {
    type = types.raw;
    default = import config."haskell-nix".nixpkgsSource ({ inherit system; } // config."haskell-nix".nixpkgsArgs);
    defaultText = fenced-code ''import config."haskell-nix".nixpkgsSource ({ inherit system; } // config."haskell-nix".nixpkgsArgs)'';
    description = ''
      The package set the driver builds with, and the one every native
      tool in its shell comes from.
    '';
  };

  haskell-nix = mkOption {
    type = types.raw;
    default = config."haskell-nix".nixpkgs.haskell-nix;
    defaultText = fenced-code ''config."haskell-nix".nixpkgs.haskell-nix'';
    description = ''
      What the overlay adds to that package set: the compilers, the hackage
      index, and the `project` function the driver calls with
      `haskell-nix.options`.
    '';
  };

  lib = mkOption {
    type = types.raw;
    default = config."haskell-nix".haskell-nix.haskellLib;
    defaultText = fenced-code ''config."haskell-nix".haskell-nix.haskellLib'';
    description = ''
      haskell.nix's own helpers, `haskellLib`: selecting a project's local
      packages, collecting components and checks, and the compiler
      plumbing a bespoke compiler needs.
    '';
  };

}
