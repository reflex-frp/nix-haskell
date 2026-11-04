# The `options` option: haskell.nix's own project options, re-imported
# from the checkout so the manual documents them and a project can set any
# of them directly.
{ lib, config, cfg }:

with lib;
with (import ../../libs/common { inherit lib; });

{

  options = mkOption {
    default = {};
    description = ''
      haskell.nix project options, passed to haskell.nix's `project`
      function as given. Any option of haskell.nix's own project modules
      can be set here (`index-state`, `cabalProjectFreeze`,
      `extra-hackages`, `pkg-def-extras`, `shell.exactDeps`, ...). The
      driver fills many of them from the common options through its
      `translation` table.
    '';
    type = types.submodule {
      imports = [
        # The documentation generator walks this submodule without the
        # translation's definitions. Defaults of haskell.nix options
        # derive from src, so the walk needs one here. The translation's
        # mkForce wins in the real evaluation.
        { config.src = mkDefault cfg.src-cleaned; }
        ({...}@projectArgs:
          let sources = map (file: "${config.inputs."haskell-nix"}/${file}") [
                paths.haskell-nix.cabal-project
                paths.haskell-nix.project-common
                paths.haskell-nix.project
              ];

              moduleArgs = projectArgs // {
                pkgs = config."haskell-nix".nixpkgs;
                haskellLib = config."haskell-nix".lib;
              };

              upstreamOptions = zipAttrsWith (name: vals: last vals)
                (map (module: (import module moduleArgs).options) sources);

              withoutFixme = text:
                concatStringsSep "\n"
                  (filter (line: !hasPrefix "# FIXME" (trim line)) (splitString "\n" text));

              cleaned = mapAttrs (_: option:
                if isString (option.description or null)
                then option // { description = withoutFixme option.description; }
                else option) upstreamOptions;

              # The default is a package set, which the manual cannot print.
              docPatches = {
                evalPackages.defaultText = upstreamOptions.evalPackages.defaultText
                  or (literalMD "haskell.nix's package set for `evalSystem`");
              };

          in {
            options = recursiveUpdate cleaned docPatches;
          }
        )
      ];
    };
  };

}
