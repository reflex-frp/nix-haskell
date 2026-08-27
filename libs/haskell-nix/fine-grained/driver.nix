# The fine-grained driver of the haskell.nix side: every selected
# package's library component resumes from a sandstone plan through
# `preBuild`. Every argument is a resolved value:
#
# - `fine-grained`: the option values
# - `project`: the project evaluated without the module this returns
# - `haskellLib`: haskell.nix's own lib
# - `pkgs`: the package set the plans' tools come from
#
# The plans read `project`, whose components differ from the final ones
# only by the restore hook, so the flags agree exactly.
#
# Example:
#
#   import ./driver.nix { inherit lib; } {
#     fine-grained = config.fine-grained;
#     project = <the plain project>;
#     haskellLib = config.haskell-nix.lib;
#     pkgs = config.haskell-nix.nixpkgs;
#   }
#   => { names = [ "frontend" ];
#        module = <a haskell.nix module restoring frontend's library>;
#      }
{ lib }:

{ fine-grained, project, haskellLib, pkgs }:

let prefix = import ../../message-prefix.nix { driver = "haskell.nix"; };

    restore-intermediates = import ../restore-intermediates.nix { inherit lib; };

    pkgSet = project.pkg-set.config;

    planDefined = project.pkg-set.options.plan-json.isDefined;

    ghc = pkgSet.ghc.package;

    hasLibrary = entry:
      (entry.components or { ${entry.component-name or "lib"} = {}; }) ? lib;

    localLibraries = lib.filter
      (entry: entry.type == "configured" && entry.style == "local" && hasLibrary entry)
      pkgSet.plan-json.install-plan;

    libraryEntry = name:
      lib.findFirst (entry: entry.pkg-name == name)
        (throw (prefix ("`fine-grained.packages` names a package the"
          + " project's plan carries no local library for: ${name}")))
        localLibraries;

    generated = name:
      pkgSet.packages.${(libraryEntry name).id}.cabal-generator != null;

    hpackCost = name: prefix ("fine-grained builds skip `${name}`: its"
      + " cabal file is generated, and a plan configures the source as"
      + " it stands. Name it in `fine-grained.packages` to keep it.");

    # A plan configures the source as it stands, so a generated cabal
    # file defeats it. `null` skips such a package. A selection that
    # names one keeps it, plan and all.
    discovered = lib.filter
      (name: !generated name || lib.warn (hpackCost name) false)
      (lib.unique (map (entry: entry.pkg-name) localLibraries));

    # A stack project defines no `plan-json`, so `null` selects nothing
    # there, and a stated selection throws through `libraryEntry`.
    names =
      if fine-grained.packages != null
      then fine-grained.packages
      else if planDefined
      then discovered
      else [];

    plan = name:
      let entry = libraryEntry name;
          package = pkgSet.packages.${entry.id};
          component = package.components.library;
          built = pkgSet.hsPkgs.${entry.id};

          # The call the component's own build configures with, so the
          # database and the dependency flags agree with it.
          configFiles = pkgSet.hsPkgs.makeConfigFiles {
            inherit component;
            inherit (package.package) identifier;
            fullName = "${name}-lib-${name}-${package.package.identifier.version}";
            flags = package.flags;
            needsProfiling = component.enableProfiling || component.enableLibraryProfiling;
            enableDWARF = component.enableDWARF
              && pkgs.stdenv.hostPlatform.isLinux
              && !pkgs.stdenv.hostPlatform.isMusl;
            prebuilt-depends = pkgSet.prebuilt-depends;
          };

          # The component's own cleaned source, split into the root the
          # plan copies and the directory it configures in.
          cleanSrc = haskellLib.rootAndSubDir
            (haskellLib.cleanCabalComponent package.package component "lib-${name}" built.src);

          configure-flags = fine-grained.configure-flags {
            inherit name component ghc pkgs;
          };

      in fine-grained.intermediates {
           inherit name pkgs ghc configure-flags;
           version = package.package.identifier.version;
           src = cleanSrc.root;
           subdir = cleanSrc.subDir;
           setup = "${built.setup}/bin/${built.setup.exeName}";
           config-files = configFiles;
           build-flags = component.setupBuildFlags;
           shim = fine-grained.ghc-shim { inherit pkgs ghc; };
           tool = fine-grained.tool;
         };

    wrap = name:
      let package = pkgSet.packages.${(libraryEntry name).id};
      in {
        # mkForce: the restore replaces any other definition of the
        # library's `preBuild`, a `previousIntermediates` restore among
        # them, and re-includes the package-level hook itself.
        components.library.preBuild = lib.mkForce (restore-intermediates {
          inherit ghc;
          pname = name;
          user-hook = package.preBuild;
          intermediates = builtins.outputOf (plan name).outPath "out";
        });
      };

    # Baked data behind one guard. haskell.nix evaluates the same module
    # list once per cross target, and only the native one restores.
    module = { pkgs, ... }: {
      config = lib.mkIf (pkgs.stdenv.hostPlatform == pkgs.stdenv.buildPlatform) {
        packages = lib.genAttrs names wrap;
      };
    };

in { inherit names module; }
