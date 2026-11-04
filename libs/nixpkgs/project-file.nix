# The project's cabal.project, as seen by the nixpkgs driver.
#
# All parsing is haskell.nix's, combined with this repo's own inlining of
# `import:` lines. The `packages:` field is deliberately not interpreted.
# haskell.nix has no nix parser for it either (real cabal reads it inside
# the plan derivation), and this driver follows the same structure. Local
# packages come from one of three places:
# - the root of the source (haskell.nix's own `packages: ./*.cabal` default)
# - an explicit `nixpkgs.options.packages` map
# - the cabal plan, when `nixpkgs.options.use-plan` is set
#
# Example:
#
#   discover { src = ./hello; }
#   => { hello = { subdir = "."; src = ./hello; }; }
#
#   discover { src = ./monorepo; explicit = { frontend.subdir = "frontend"; }; }
#   => { frontend = { subdir = "frontend"; src = ./monorepo/frontend; }; }
#
#   sourceRepoStanzas null (projectFileText "cabal.project" ./project)
#   => [ { url = "https://github.com/reflex-frp/reflex-dom";
#          ref = "master"; sha256 = null; subdirs = [ "reflex-dom" ]; } ]
#
#   packageNameIn ./hello              # holds hello.cabal (or package.yaml)
#   => "hello"
#
#   packageAt ./monorepo "source-repository-packages.dep" "frontend"
#   => { name = "frontend"; value = ./monorepo/frontend; }
{ pkgs
, haskell-nix-src ? null
}:

with pkgs.lib;
with (import ../common { inherit (pkgs) lib; });

let prefix = message-prefix { driver = "nixpkgs"; };
    parser = import "${haskell-nix-src}/${paths.haskell-nix.cabal-project-parser}" { inherit pkgs; };

    inline-cabal-project = (import ../cabal.nix { inherit pkgs; }).inline-cabal-project;

    # The name of the cabal package in `dir`, or null when there is none.
    # Cabal requires the .cabal file to be named after the package, so the
    # filename is authoritative. hpack projects carry the name in
    # package.yaml.
    packageNameIn = dir:
      let entries = builtins.readDir dir;

          files = filterAttrs (_: t: t == "regular" || t == "symlink") entries;

          cabals = filter (hasSuffix ".cabal") (attrNames files);

          nameLine = line:
            let m = builtins.match "name[[:space:]]*:[[:space:]]*\"?([^\"]+)\"?[[:space:]]*" line;
            in if m == null
               then []
               else [ (head m) ];

          hpackNames = concatMap nameLine
            (splitString "\n" (builtins.readFile (dir + "/package.yaml")));

      in if length cabals > 1
         then throw (prefix "${toString dir} contains more than one .cabal file")
         else if cabals != []
         then removeSuffix ".cabal" (head cabals)
         else if entries ? "package.yaml"
         then
           if hpackNames == []
           then throw (prefix "no name field found in ${toString dir}/package.yaml")
           else head hpackNames
         else null;

    # The project file with `import:` lines inlined, or null when the source
    # carries none.
    projectFileText = fileName: src:
      if builtins.pathExists (src + "/${fileName}")
      then inline-cabal-project src fileName
      else null;

    # source-repository-package stanzas of project text:
    # [ { url; ref or rev; sha256; subdirs; } ]
    # Hashes resolve through `--sha256` comments or the given sha256map.
    sourceRepoStanzas = sha256map: text:
      concatMap (b: optional (b ? sourceRepo) b.sourceRepo)
        (parser.parseSourceRepositoryPackages "cabal.project" sha256map {} text).sourceRepos;

    # The directory a subdir spec names, `.` meaning the source root itself.
    dirAt = src: d:
      if d == "."
      then src
      else src + "/${d}";

    # Local packages: { <package-name> = { subdir; src; }; }. An explicit map
    # (keyed by package name) takes precedence; otherwise the package at the
    # root of the source is the project.
    discover = { src, explicit ? null }:
      let noRootPackage = throw (prefix "no .cabal file or package.yaml at the root of the project source; for a multi-package project set nixpkgs.options.packages or nixpkgs.options.use-plan");

          rootPackage =
            let name = packageNameIn src;
            in if name == null
               then noRootPackage
               else { ${name} = { subdir = "."; src = src; }; };

      in if explicit != null
         then mapAttrs (_: p: { inherit (p) subdir; src = dirAt src p.subdir; }) explicit
         else rootPackage;

    # The cabal package a subdir of `src` holds, as a name/value pair of
    # package name to directory. `context` names the stanza in the error.
    packageAt = src: context: d:
      let dir = dirAt src d;
          name = packageNameIn dir;
      in if name == null
         then throw (prefix "no cabal package in ${toString dir} (${context})")
         else nameValuePair name dir;

in {
  inherit packageNameIn discover projectFileText sourceRepoStanzas packageAt;
}
