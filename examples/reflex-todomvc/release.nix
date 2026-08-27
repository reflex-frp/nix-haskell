# Every combination of driver, compiler and cross target this example is
# meant to work for. Each is built two ways: as the drivers build it, and
# as a person would inside the project's shell. `bundle` is the same matrix
# again, carrying what each target ships rather than what it links: the
# executable through that target's optimizer, and for wasm the JSFFI
# bindings beside it.
#
#   nix-build release.nix -A build
#   nix-build release.nix -A shell-build
#   nix-build release.nix -A bundle
#   nix-build release.nix -A build.haskell-nix.ghc912.wasi32
#   nix-build release.nix -A bundle.haskell-nix.ghc912.wasi32.optimized
#   nix-build release.nix -A fine-grained.haskell-nix.ghc912
#
# `wasm-meta` is the same matrix with the wasm target's compiler taken from
# the ghc-wasm-meta pin instead of the driver's own.
#
# `fine-grained` is the native executable per driver and compiler, with the
# library built one module per derivation. Those rows appear only where the
# Nix reading this carries dynamic derivations, like the root release.
#
# Combinations that cannot work are absent rather than failing. The nixpkgs
# driver has no 9.14 Haskell package set worth building against. That
# driver's own compiler is therefore 9.12, and it reaches a wasm target
# only through the ghc-wasm-meta pin.
{ system ? builtins.currentSystem, inputs ? {} }:

let nix-haskell = import ../.. { inherit system inputs; };

    project = modules: nix-haskell ([ (import ./project.nix) ] ++ modules);

    lib = (project []).pkgs.lib;

    ghcName = series: "ghc${lib.replaceStrings [ "." ] [ "" ] series}";

    wasmMeta = series: {
      imports = [ (import ./wasm-meta.nix { inherit series; }) ];

      # The bindist is a wasm compiler the nixpkgs driver can carry cross
      # tools for, and the driver's own is not. The shell therefore gains
      # the target here rather than in the project. `mkForce`, since the
      # option is typed `unspecified` and two selectors would otherwise be
      # merged by applying both and joining what they return.
      nixpkgs.shell.crossPlatforms = lib.mkForce (ps: with ps; [ ghcjs wasi32 ]);
    };

    variant = series: withWasmMeta: modules:
      project ([ { compiler.name = ghcName series; } ]
        ++ lib.optional withWasmMeta (wasmMeta series)
        ++ modules);

    # The exe as each driver names it: haskell.nix has a tree of components, the
    # nixpkgs driver one derivation per package.
    driverExe = {
      haskell-nix = p: platform:
        p.haskell-nix.project.projectCross.${platform}.hsPkgs.reflex-todomvc.components.exes.reflex-todomvc;
      nixpkgs = p: platform:
        p.nixpkgs.project.projectCross.${platform}.packages.reflex-todomvc;
    };

    built = driver: series: withWasmMeta: platforms:
      let p = variant series withWasmMeta [];
      in lib.genAttrs platforms (platform: driverExe.${driver} p platform);

    # `nix-build` descends into an attribute set only where it is told it may,
    # so every level of a matrix says so. Without this, building the file, or
    # any of its matrices by name, finds no derivation and does nothing.
    walkable = attrs:
      let descend = value:
            if lib.isAttrs value && ! lib.isDerivation value
            then walkable value
            else value;
      in lib.mapAttrs (_: descend) attrs
         // { recurseForDerivations = true; };

    # Naming the executable puts a bundle on the tree. For a javascript
    # target, it also installs the `.jsexe` closure-compiler works on.
    namedExe = platform:
      { platforms.${platform}.packages.reflex-todomvc.components.exes.reflex-todomvc = {}; };

    # What a target ships, read off the tree rather than assembled here: the
    # executable through that target's optimizer, and for wasm the JSFFI
    # bindings its binary cannot be instantiated without. A javascript target
    # has none, and the `null` it answers with is dropped rather than built.
    bundled = driver: series: withWasmMeta: platforms:
      lib.genAttrs platforms (platform:
        let p = variant series withWasmMeta [ (namedExe platform) ];
            exe = p.config.${driver}.platforms.${platform}
                    .packages.reflex-todomvc.components.exes.reflex-todomvc;
        in lib.filterAttrs (_: artifact: artifact != null) exe.bundles);

    # The name of the wrapper that puts a cross target's tools in front of the
    # ones the shell carries for the build platform. It is the target's own
    # prefix, so the compiler a target is built with decides it: haskell.nix
    # builds its wasm compiler for wasm32-unknown-wasi, while the bindist is
    # built for wasm32-wasi.
    dispatcher = withWasmMeta: platform:
      if platform == "ghcjs"
      then "javascript-unknown-ghcjs"
      else if withWasmMeta
      then "wasm32-wasi"
      else "wasm32-unknown-wasi";

    # The build a person would run, in the shell they would run it in. cabal
    # needs no package index: the shell's package database already carries
    # everything the project depends on. A configuration naming no
    # repository keeps cabal from fetching one it cannot reach.
    shellBuilt = driver: series: withWasmMeta: platforms:
      let p = variant series withWasmMeta [];
          shell = p.${driver}.project.shell;
      in lib.genAttrs platforms (platform:
        shell.overrideAttrs (old: {
          name = lib.concatStringsSep "-" ([ "reflex-todomvc" driver ]
            ++ lib.optional withWasmMeta "wasm-meta"
            ++ [ (ghcName series) platform "shell-build" ]);

          src = p.${driver}.project.config.src-cleaned;

          phases = [ "unpackPhase" "buildPhase" "installPhase" ];

          buildPhase = ''
            export HOME=$TMPDIR
            export CABAL_CONFIG=$TMPDIR/cabal.config
            echo 'jobs: $ncpus' > $CABAL_CONFIG
            echo 'active-repositories: :none' >> cabal.project.local

            ${dispatcher withWasmMeta platform} cabal build --offline exe:reflex-todomvc
          '';

          installPhase = ''
            mkdir -p $out
            for artifact in dist-newstyle/build/*/*/reflex-todomvc-*/x/reflex-todomvc/build/reflex-todomvc/*; do
              case "$artifact" in
                *-tmp) continue ;;
              esac
              cp -r "$artifact" $out/
            done
          '';
        }));

    # The fine-grained variant: the selection is stated, because cabal
    # counts the source-repository-packages as local too, and a row bounds
    # its work to the project's own package. Haddock reads sources rather
    # than compiled modules, and the nixpkgs driver would warn about the
    # second read.
    fineGrainedModule = {
      fine-grained = {
        enable = true;
        packages = [ "reflex-todomvc" ];
      };
      packages.reflex-todomvc.doHaddock = false;
    };

    # The native executable as each driver names it. The nixpkgs driver
    # builds the library and the executable in one derivation.
    fineGrainedExe = {
      haskell-nix = p:
        p.haskell-nix.project.hsPkgs.reflex-todomvc.components.exes.reflex-todomvc;
      nixpkgs = p:
        p.nixpkgs.project.packages.reflex-todomvc;
    };

    fineGrainedBuilt = driver: series:
      fineGrainedExe.${driver} (variant series false [ fineGrainedModule ]);

    # The one matrix of driver, compiler series, wasm-meta and cross targets.
    # Each result set applies its own leaf function to every cell.
    matrix = leaf: walkable {

      haskell-nix = {
        ghc912 = leaf "haskell-nix" "9.12" false [ "ghcjs" "wasi32" ];
        ghc914 = leaf "haskell-nix" "9.14" false [ "ghcjs" "wasi32" ];
      };

      nixpkgs = {
        ghc912 = leaf "nixpkgs" "9.12" false [ "ghcjs" ];
      };

      wasm-meta = {

        haskell-nix = {
          ghc912 = leaf "haskell-nix" "9.12" true [ "ghcjs" "wasi32" ];
          ghc914 = leaf "haskell-nix" "9.14" true [ "ghcjs" "wasi32" ];
        };

        nixpkgs = {
          ghc912 = leaf "nixpkgs" "9.12" true [ "ghcjs" "wasi32" ];
          ghc914 = leaf "nixpkgs" "9.14" true [ "ghcjs" "wasi32" ];
        };

      };

    };

in {

  build = matrix built;

  bundle = matrix bundled;

  shell-build = matrix shellBuilt;

} // lib.optionalAttrs (builtins ? outputOf) {

  fine-grained = walkable {

    haskell-nix = {
      ghc912 = fineGrainedBuilt "haskell-nix" "9.12";
      ghc914 = fineGrainedBuilt "haskell-nix" "9.14";
    };

    nixpkgs = {
      ghc912 = fineGrainedBuilt "nixpkgs" "9.12";
    };

  };

}
