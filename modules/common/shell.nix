# The `shell` option: the development shell's packages, tools, inputs and
# hooks.
{ lib }:

with lib;
with (import ../../libs/common { inherit lib; });

{

  shell = mkOption {
    default = {};
    description = ''
      The development shell.
    '';
    type = types.submodule {
      options = {

        packages = mkOption {
          type = types.nullOr types.unspecified;
          default = null;
          defaultText = literalMD ''
            `null` (selects every local package that is not a
            `source-repository-packages` entry)
          '';
          apply = selection:
            let resolveEntry = ps: entry:
                  if ! builtins.isString entry
                  then [ entry ]
                  else
                    let package = ps.${entry} or null;
                    in optional (package != null) package;

                resolveAll = ps: concatMap (resolveEntry ps) (selection ps);

            in if selection == null
               then null
               else resolveAll;
          description = ''
            Package selection function. It takes a set of Haskell packages
            and returns a subset. The selected packages and all of their
            dependencies appear in `ghc-pkg list`.

            An entry is a package or a package name (a string). Use a name
            for a package whose availability depends on the platform.
          '';
          example = fenced-code ''
            ps: with ps; [
              common
              frontend
              "backend" # Provided by name so that it is only included when it's among `ps`
            ]
          '';
        };

        tools = mkOption {
          type = types.attrsOf types.raw;
          default = {};
          description = ''
            Haskell tools available in the shell, keyed by executable name.
            The value is one of:

            - a version request such as `"latest"`
            - a version string
            - a tool argument set
          '';
          example = fenced-code ''{ cabal = "latest"; haskell-language-server = "latest"; }'';
        };

        buildInputs = mkOption {
          type = types.listOf types.package;
          default = [];
          description = ''
            Extra packages available in the shell.
          '';
          example = fenced-code ''[ pkgs.sqlite ]'';
        };

        nativeBuildInputs = mkOption {
          type = types.listOf types.package;
          default = [];
          description = ''
            Extra native packages available in the shell.
          '';
          example = fenced-code ''[ pkgs.pkg-config ]'';
        };

        shellHook = mkOption {
          type = types.lines;
          default = "";
          description = ''
            Shell hook to run when entering the shell.
          '';
          example = "export MY_APP_PORT=8000";
        };

        withHoogle = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Provide a hoogle database over the shell's package set.
          '';
        };

        crossPlatforms = mkOption {
          type = types.unspecified;
          default = _: [];
          defaultText = fenced-code ''ps: []'';
          description = ''
            Selects the cross-compilation targets from an attribute set
            keyed by `pkgs.pkgsCross` platform names.
          '';
          example = fenced-code ''ps: with ps; [ ghcjs wasi32 ]'';
        };

      };
    };
  };

}
