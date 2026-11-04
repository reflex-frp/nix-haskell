# Import the nixpkgs behind `pkgs` again, with arguments changed by an attrset
# or by a function of the old arguments. Nested attrsets merge.
#
# Example:
#   import ./reimport.nix pkgs { config.allowUnfree = true; }
#   => the same package set, with allowUnfree added to the config of `pkgs`
#
#   import ./reimport.nix pkgs (old: { overlays = old.overlays ++ [ overlay ]; })
#   => the same package set, with one more overlay
#
#   import ./reimport.nix pkgs { system = pkgs.stdenv.buildPlatform.system; }
#   => pkgs itself
pkgs: change:

with (import ../common { inherit (pkgs) lib; });

let oldArgs = {
      system = pkgs.stdenv.buildPlatform.system;
      inherit (pkgs) path overlays config;
    };

    newArgs = pkgs.lib.toFunction change oldArgs;

    args = pkgs.lib.recursiveUpdate oldArgs newArgs;

    sameAsOld = name: and [
      (builtins.elem name [ "system" "path" ])
      (toString newArgs.${name} == toString oldArgs.${name})
    ];

    unchanged = builtins.all sameAsOld (builtins.attrNames newArgs);

in if unchanged
   then pkgs
   else import args.path (removeAttrs args [ "path" ])
