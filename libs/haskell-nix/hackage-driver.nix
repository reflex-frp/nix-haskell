# haskell.nix reads extra hackage indexes but cannot build one from source
# directories, so this builds one. The cabal solver reads it beside the
# real one and, where the constraints match, picks the
# packages from this overlay.
#
# A simpler take on:
# - https://github.com/ilyakooo0/haskell-nix-extra-hackage/blob/master/default.nix
# - https://github.com/mlabs-haskell/mlabs-tooling.nix/blob/main/mk-hackage.nix
#
# Example:
#
#   import ./hackage-driver.nix {
#     inherit pkgs;
#     modules = [ { name = "dep-b"; version = "0.1.0.0"; src = ./dep-b; } ];
#   }
#   => { extra-hackage-tarballs.overlay = <01-index.tar.gz with dep-b>;
#        extra-hackages = [ <imported hackage-to-nix output> ];
#        package-overlays = [ { packages.dep-b.src = <mkForce ./dep-b>; } ];
#        generatedHackage = <the hackage-to-nix output, before import>;
#        buildCommands = [ "mkdir -p $packagedef/dep-b/0.1.0.0\n..." ];
#        modules = <the argument, verbatim>;
#      }
#
#   import ./hackage-driver.nix { inherit pkgs; }
#   => the same shape with an empty index: `extra-hackages` still holds one
#      entry, and `package-overlays` is empty
{ pkgs, modules ? [ ] }:

let packageDef = { name, version, src, signatures ? [ ], type ? "Targets", expires ? null }:
      let cabalHash = builtins.hashFile "sha256" "${src}/${name}.cabal";

          target = {
            hashes = {
              sha256 = cabalHash;
            };
            length = 1;
          };

      in {
        inherit signatures;
        signed = {
          "_type" = type;
          inherit expires;
          targets = {
            "<repo>/package/${name}-${version}.tar.gz" = target;
          };
          version = 0;
        };
      };

    commandFor = a:
      let json = builtins.toFile "${a.name}.json"
            (builtins.toJSON (packageDef { inherit (a) name version src; }));
      in ''
        mkdir -p $packagedef/${a.name}/${a.version}
        cp ${json} $packagedef/${a.name}/${a.version}/package.json
        cp ${a.src}/*.cabal $packagedef/${a.name}/${a.version}
      '';

    writePackageDefs = defs: pkgs.runCommand "index.tar.gz" {
      outputs = [ "packagedef" "out" ];
    } ''
      set -eux
      ${builtins.concatStringsSep "\n" defs}
      mkdir -p $packagedef
      cd $packagedef
      tar --sort=name --owner=root:0 --group=root:0 --mtime='UTC 2009-01-01' -hczvf $out */*/*
    '';

    genHackageForNix = hackagetar: pkgs.runCommand "hackage-for-nix" { } ''
      cp ${hackagetar} 01-index.tar.gz
      ${pkgs.gzip}/bin/gunzip 01-index.tar.gz
      ${pkgs.haskell-nix.nix-tools.exes.hackage-to-nix}/bin/hackage-to-nix $out 01-index.tar "https://hackagefornix/"
    '';

    buildCommands = map commandFor modules;

    indexTarball = (writePackageDefs buildCommands).out;

    extra-hackage-tarballs = {
      overlay = indexTarball;
    };

    generatedHackage = genHackageForNix indexTarball;

    package-overlays = map (a: { packages.${a.name}.src = pkgs.lib.mkForce a.src; }) modules;

    extra-hackages = [
      (import generatedHackage)
    ];

in {
  inherit modules buildCommands generatedHackage package-overlays;
  inherit extra-hackage-tarballs extra-hackages;
}
