# Packages from outside the project source: local checkouts added to the
# project, and packages made visible to dependency resolution without a
# Hackage release.
{ lib }:

with lib;
with (import ../../libs/common { inherit lib; });

{

  source-repository-packages = mkOption {
    type = types.attrsOf (types.either types.path types.attrs);
    default = {};
    description = ''
      Local packages to add to the project. A source is anything `inputs`
      accepts. A packed thunk directory can be given as-is and resolves
      to the source it pins.

      `subdir` selects packages within the source, so a multi-package
      repository needs one entry rather than one per package.
    '';
    example = fenced-code ''
      {
        obelisk-frontend = deps.obelisk + "/lib/frontend";
        obelisk-backend = {
          src = deps.obelisk + "/lib/backend";
          condition = "!arch(javascript)";
        };

        reflex-dom = deps.reflex-dom + "/reflex-dom";
        reflex-dom-core = deps.reflex-dom + "/reflex-dom-core";
        reflex = deps.reflex;
      }
    '';
  };

  hackage-overlays = mkOption {
    type = types.listOf types.attrs;
    default = [];
    description = ''
      Packages to make visible to dependency resolution without being
      published to Hackage. One example is obelisk-generated-static.
    '';
    example = fenced-code ''
      [
        {
          name = "android-activity";
          version = "0.1.1";
          src = pkgs.fetchFromGitHub {
            owner = "obsidiansystems";
            repo = "android-activity";
            rev = "2bc40f6f907b27c66428284ee435b86cad38cff8";
            sha256 = "sha256-AIpbe0JZX68lsQB9mpvR7xAIct/vwQAARVHAK0iChV4=";
          };
        }
      ]
    '';
  };

}
