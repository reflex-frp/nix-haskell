# The repo's checks, exposed as `checks.<system>` by the flake:
#
#   translation-totality        every common option is translated by every
#                               driver, in both directions (pure eval)
#   compiler-spec               how a compiler is resolved: driver fallbacks,
#                               derived names, the attributes spliced onto a
#                               compiler package, per-platform dispatch and
#                               its toolchain (pure eval)
#   bundle-optimizer-spec       which layer of the bundle optimizer settings
#                               decides a field, and what a disabled optimizer
#                               does instead (pure eval)
#   bundle-optimizers           wasm-opt and closure-compiler run over the
#                               smallest inputs they accept, with the flag sets
#                               the settings produce
#   package-arguments-spec      a raw mkDerivation argument set through
#                               nixpkgs.options.package-arguments lands on
#                               the package derivation (pure eval)
#   fine-grained-spec           both drivers' plan configure flags follow the
#                               package's own fields, and a selection that
#                               names no package changes no derivation on
#                               either driver (evaluates the hello plan)
#   cross-target-row-spec       a user-supplied cross-target row is a full
#                               target: options, registry, node opt-out,
#                               and settings tolerance (pure eval)
#   every-option-<driver>       the every-option fixture instantiates through
#                               the driver's whole translation (no compiling)
#   hello-<driver>              the hello example builds
#
# Runnable without the flake: nix-build tests -A translation-totality
{ system ? builtins.currentSystem
, inputs ? {}
, pkgs ?
    if inputs ? nixpkgs
    then import inputs.nixpkgs { inherit system; }
    else import ../pins/nixpkgs { inherit system; }
}:

with pkgs.lib;

let eval = import ../eval.nix { inherit system pkgs inputs; };

    # ------------------------------------------------------------------------
    # Fixtures
    # ------------------------------------------------------------------------

    drivers = [ "haskell-nix" "nixpkgs" ];

    fixture = eval ./fixtures/every-option.nix;

    hello = eval (import ../examples/hello/project.nix);

    common = import ../libs/driver/option-names.nix {
      inherit (pkgs) lib;
      options = fixture.options;
      excludes = drivers;
    };

    # ------------------------------------------------------------------------
    # translation-totality
    # ------------------------------------------------------------------------

    translation-totality =
      let check = driver:
            let keys = attrNames fixture.config.${driver}.translation;
                missing = subtractLists keys common;
                stale = subtractLists common keys;
            in optional (missing != [])
                 "the ${driver} driver does not translate: ${concatStringsSep ", " missing}"
            ++ optional (stale != [])
                 "the ${driver} driver translates options that do not exist: ${concatStringsSep ", " stale}";
          failures = concatMap check drivers;
      in if failures == []
         then pkgs.runCommand "translation-totality" {} "echo ok > $out"
         else throw (concatStringsSep "\n" failures);

    # ------------------------------------------------------------------------
    # compiler-spec
    # ------------------------------------------------------------------------

    # How a compiler is resolved: the name a driver falls back to, the names
    # derived from a compiler package, the attributes spliced onto it, and the
    # dispatch of a per-platform entry. Pure eval, so the stubs are never
    # built.
    compiler-spec =
      let stub = version: derivation {
            name = "stub-ghc";
            builder = "/bin/sh";
            inherit system;
          } // { inherit version; };

          sdk = derivation { name = "stub-sdk"; builder = "/bin/sh"; inherit system; };

          project = compiler: eval {
            name = "compiler-spec";
            src = ../examples/hello;
            inherit compiler;
          };

          unset = project {};
          package = project { package = stub "9.12.2"; };
          # a name of its own, and a version the name does not follow from
          named = project {
            name = "ghc912";
            package = stub "9.12.4.20260731";
            haskell-nix.libDir = "lib";
          };
          cross = project {
            name = "ghc912";
            platforms.wasi32 = {
              package = stub "9.12.4.20260731";
              haskell-nix.extraNonReinstallablePkgs = [ "system-cxx-std-lib" ];
              toolchain = {
                package = sdk;
                cc = "clang";
                ar = "ar";
                ld = "ld";
                strip = "strip";
              };
            };
          };

          resolved = p: import ../libs/compiler { inherit (pkgs) lib; } {
            compiler = p.config.compiler;
            inherit system;
          };

          selection = p: pkgs':
            p.config."haskell-nix".translation."compiler.name".set.compilerSelection pkgs';
          fakePkgs = platform: {
            stdenv.targetPlatform = platform;
            haskell-nix = { resolve-compiler-name = n: n; compiler.ghc912 = "stock-ghc912"; };
          };
          native = systems.elaborate system;
          wasi = systems.elaborate systems.examples.wasi32;

          nativeOf = p: (resolved p).native;
          wasiOf = p: (resolved p).resolve "wasi32";

          # each driver's own compiler when the project names none, and a
          # driver default still reaching a field the project left alone
          fallbackFailures =
            optional (unset.config."haskell-nix".compiler.name != "ghc914")
              "the haskell.nix driver does not fall back to ghc914"
            ++ optional (unset.config.nixpkgs.compiler.name != "ghc912")
              "the nixpkgs driver does not fall back to ghc912"
            ++ optional (cross.config.nixpkgs.compiler.platforms.wasi32.targetPrefix != null)
              "a platform entry loses the fields the project did not set";

          # names derived from a package, the stock name derived from the
          # version rather than from the name, and the attributes both
          # drivers read off a compiler
          derivationFailures =
            optional ((nativeOf package).name != "ghc9122")
              "a compiler package's name is not derived from its version"
            ++ optional ((nativeOf named).name != "ghc912")
              "the name the project gave is not kept"
            ++ optional ((nativeOf named).stockName != "ghc9124")
              "the stock name is not derived from the version alone"
            ++ optional ((nativeOf named).annotated.libDir or null != "lib")
              "libDir is not spliced onto the compiler"
            ++ optional ((nativeOf named).annotated.haskellCompilerName or null != "ghc-9.12.4.20260731")
              "haskellCompilerName is not derived from the version"
            ++ optional ((nativeOf named).annotated.enableShared or null != true)
              "enableShared does not default to true";

          # platform lookup, and its fall back to the compiler above the table
          platformFailures =
            optional ((resolved cross).targetKey wasi != "wasi32")
              "a target platform does not find its own entry"
            ++ optional ((resolved cross).targetKey native != system)
              "the native platform does not resolve to the native system"
            ++ optional ((resolved cross).resolve "ghcjs" != (nativeOf cross))
              "a platform without an entry does not use the compiler above the table"
            ++ optional (! (resolved cross).anyToolchain)
              "a toolchain on a platform entry is not noticed"
            ++ optional ((wasiOf cross).toolchainFlags != [
                 "--with-gcc=${sdk}/bin/clang"
                 "--with-ar=${sdk}/bin/ar"
                 "--with-ld=${sdk}/bin/ld"
                 "--with-strip=${sdk}/bin/strip"
               ])
              "the toolchain's configure flags are not what a build is given"
            ++ optional (! (resolved cross).anyExtraNonReinstallablePkgs)
              "boot packages named by a platform entry are not noticed"
            ++ optional ((wasiOf cross).extraNonReinstallablePkgs != [ "system-cxx-std-lib" ])
              "a platform entry's boot packages do not reach the driver";

          # a compiler with nothing to name it, and a platform that is not one
          errorFailures =
            optional (builtins.tryEval (nativeOf (project {
                 package = derivation { name = "nameless"; builder = "/bin/sh"; inherit system; };
               })).name).success
              "a compiler with no version and no name does not fail"
            ++ optional (builtins.tryEval
                 ((resolved (project { platforms.nonsense.name = "ghc912"; })).targetKey wasi)).success
              "a platform key that names no platform does not fail";

          # the drivers, given a compiler package
          selectionFailures =
            optional ((selection package (fakePkgs native)).ghc9122.name or null != (stub "9.12.2").name)
              "the haskell.nix driver's compilerSelection does not return the package"
            ++ optional ((selection cross (fakePkgs native)).ghc912 or null != "stock-ghc912")
              "a project without its own native compiler does not use the driver's"
            ++ optional ((selection cross (fakePkgs wasi)).ghc912.name or null != (stub "9.12.4.20260731").name)
              "a platform entry is not dispatched on the target platform"
            ++ optional (package.config.nixpkgs.haskellPackages.ghc.name or null != (stub "9.12.2").name)
              "the nixpkgs driver's base package set does not carry the compiler";

          failures =
            fallbackFailures
            ++ derivationFailures
            ++ platformFailures
            ++ errorFailures
            ++ selectionFailures;
      in if failures == []
         then pkgs.runCommand "compiler-spec" {} "echo ok > $out"
         else throw (concatStringsSep "\n" failures);

    # ------------------------------------------------------------------------
    # bundle-optimizer-spec
    # ------------------------------------------------------------------------

    # Which layer of the bundle optimizer settings decides a field, read off the
    # command line each optimizer would run. The fixture states a different
    # field at every layer, so a resolution that reached for the wrong one shows
    # up as the wrong flag. Pure eval: nothing is optimized.
    bundle-optimizer-spec =
      let wasmOpt = names: fixture.config.wasm-optimize (names // { wasm = "/probe.wasm"; });
          closureCompiler = names: fixture.config.js-optimize (names // { jsexe = "/probe.jsexe"; });

          commandOf = drv: drv.drvAttrs.buildCommand;

          # The flags become a match pattern, and a store path may not
          # appear in a pattern. The command line they are searched in may
          # contain one.
          runs = flags: drv:
            hasInfix (builtins.unsafeDiscardStringContext flags) (commandOf drv);

          off = eval {
            name = "bundle-optimizer-off";
            src = ../examples/hello;
            wasm-opt.enable = false;
            closure-compiler.enable = false;
          };

          externs = ./fixtures/every-option-externs.js;

          onTarget = fixture.config.platforms.wasi32.packages.every-option;

          packageBundles = onTarget.bundles;

          exeBundle = onTarget.components.exes.every-option.bundles;

          # The module a driver adds for the executables a project named, given
          # the target it finds itself in and a project holding one of the two
          # packages it was told about.
          installJsexe = isGhcjs:
            import ../libs/haskell-nix/install-jsexe.nix {
              inherit (pkgs) lib;
              exes = { frontend = [ "frontend" ]; absent-package = [ "absent" ]; };
            } {
              config.packages.frontend = {};
              pkgs = { stdenv.hostPlatform = { inherit isGhcjs; }; };
            };

          installed = (installJsexe true).config.content;

          # which layer decides a field: nothing named, a package and one of
          # its executables, a target and the layers under it, a layer that
          # states nothing, a package with no entry at all, the strip that
          # follows, and what closure-compiler is given
          layerFailures =
            optional (! runs "-all -Oz --converge" (wasmOpt {}))
              "an optimizer told no names does not take the settings of the tool itself"
            ++ optional (! runs "-all -O3 --converge" (wasmOpt { package = "every-option"; }))
              "a package's own level does not beat the tool's"
            ++ optional (! runs "-all -O3 --strip-dwarf" (wasmOpt {
                 package = "every-option"; exe = "every-option";
               }))
              "an executable's own flags do not beat its package's"
            ++ optional (! runs "-all -Os --converge" (wasmOpt { platform = "wasi32"; }))
              "a target's own level does not beat the tool's"
            ++ optional (! runs "-all -Os --low-memory-unused" (wasmOpt {
                 platform = "wasi32"; package = "every-option";
               }))
              "a package on one target does not beat that package on any target"
            ++ optional (! runs "-all -O4 --low-memory-unused" (wasmOpt {
                 platform = "wasi32"; package = "every-option"; exe = "every-option";
               }))
              "an executable on one target does not beat its package on that target"
            ++ optional (! runs "-all -Oz --converge" (wasmOpt { package = "absent-package"; }))
              "a package entry stating nothing does not fall through to the tool's settings"
            ++ optional (! runs "-all -Oz --converge" (wasmOpt { package = "no-such-package"; }))
              "a package with no entry is not the same as one stating nothing"
            ++ optional (! runs "wasm-tools strip -a optimized.wasm -o $out" (wasmOpt {}))
              "the custom sections are not stripped after wasm-opt has run"
            ++ optional (! runs "--externs $out/all.externs.js --compilation_level SIMPLE" (closureCompiler {}))
              "the jsexe's own externs are not passed ahead of the settings"
            ++ optional (! runs "--compilation_level WHITESPACE_ONLY --externs ${externs} --warning_level QUIET"
                 (closureCompiler { package = "every-option"; exe = "every-option"; }))
              "closure-compiler's level, externs and flags do not come from the layers that state them";

          # disabled, where each optimizer copies its input through instead
          disabledFailures =
            optional (commandOf (off.config.wasm-optimize { wasm = "/probe.wasm"; })
                 != "cp /probe.wasm $out\n")
              "a disabled wasm-opt does not copy its input through"
            ++ optional (commandOf (off.config.js-optimize { jsexe = "/probe.jsexe"; })
                 != "cp -r /probe.jsexe $out\n")
              "a disabled closure-compiler does not copy its input through";

          # the bundles of a target, which only a driver can answer for. What
          # one is when a driver does answer takes a cross build, so the
          # example is where that is shown.
          bundleTreeFailures =
            optional (attrNames packageBundles != [ "every-option" ])
              "a package's bundles are not keyed by the executables it names"
            ++ optional (exeBundle.optimized != null || exeBundle.jsffi != null)
              "a bundle read outside a driver is not null";

          # the jsexe install that gives closure-compiler a directory to work on
          jsexeInstallFailures =
            optional (! hasInfix "cp -r dist/build/frontend/frontend.jsexe $out/bin/"
                 installed.packages.frontend.components.exes.frontend.postInstall)
              "a named executable's jsexe is not installed beside it"
            ++ optional (installed.packages ? absent-package)
              "a jsexe install is attached to a package the project does not have"
            ++ optional ((installJsexe false).config.condition != false)
              "the jsexe install is not confined to a javascript target";

          failures =
            layerFailures
            ++ disabledFailures
            ++ bundleTreeFailures
            ++ jsexeInstallFailures;
      in if failures == []
         then pkgs.runCommand "bundle-optimizer-spec" {} "echo ok > $out"
         else throw (concatStringsSep "\n" failures);

    # ------------------------------------------------------------------------
    # bundle-optimizers
    # ------------------------------------------------------------------------

    # The flag sets the tools are actually handed, over the smallest inputs they
    # accept, so a flag one of them rejects fails here rather than in a project
    # after a cross build.
    bundle-optimizers =
      let project = eval { name = "bundle-optimizers"; src = ../examples/hello; };

          off = eval {
            name = "bundle-optimizers-off";
            src = ../examples/hello;
            wasm-opt.enable = false;
            closure-compiler.enable = false;
          };

          # An exported function to keep, and an unreachable one for the
          # optimizer to drop.
          wat = pkgs.writeText "tiny.wat" ''
            (module
              (func $unreachable (result i32) (i32.const 41))
              (func (export "answer") (result i32) (i32.const 42)))
          '';

          wasm = pkgs.runCommand "tiny.wasm" {
            nativeBuildInputs = [ pkgs.wasm-tools ];
          } "wasm-tools parse ${wat} -o $out";

          jsexe = pkgs.runCommand "tiny.jsexe" {} ''
            mkdir -p $out
            cat > $out/all.js <<'JS'
            var unreachable = function() { return 41; };
            globalThis.answer = function() { return 42; };
            JS
            cat > $out/all.externs.js <<'JS'
            /** @externs @suppress {duplicate} */
            /** @type {*} */
            var globalThis;
            JS
          '';

      in pkgs.runCommand "bundle-optimizers" {
        nativeBuildInputs = [ pkgs.wasm-tools pkgs.nodejs ];
      } ''
        optimizedWasm=${project.config.wasm-optimize { inherit wasm; }}
        optimizedJs=${project.config.js-optimize { inherit jsexe; }}/all.js

        # still a module, and smaller for having lost the function nothing reaches
        wasm-tools validate $optimizedWasm
        [ "$(stat -c%s $optimizedWasm)" -lt "$(stat -c%s ${wasm})" ]

        # still a program, and smaller for the same reason
        node --check $optimizedJs
        [ "$(stat -c%s $optimizedJs)" -lt "$(stat -c%s ${jsexe}/all.js)" ]

        # disabled, each input arrives byte for byte
        cmp ${wasm} ${off.config.wasm-optimize { inherit wasm; }}
        cmp ${jsexe}/all.js ${off.config.js-optimize { inherit jsexe; }}/all.js

        echo ok > $out
      '';

    # ------------------------------------------------------------------------
    # package-arguments-spec
    # ------------------------------------------------------------------------

    # A raw mkDerivation argument set through `package-arguments` lands on
    # the package's derivation.
    package-arguments-spec =
      let project = eval {
            name = "package-arguments";
            src = ../examples/hello;
            nixpkgs.options.package-arguments.hello.postInstall = "cp -r static $out";
          };
          postInstall = project.config.nixpkgs.project.packages.hello.postInstall;
      in if postInstall == "cp -r static $out"
         then pkgs.runCommand "package-arguments-spec" {} "echo ok > $out"
         else throw "package-arguments: postInstall is ${builtins.toJSON postInstall}";

    # ------------------------------------------------------------------------
    # fine-grained-spec
    # ------------------------------------------------------------------------

    # A plan's configure flags follow the package's own fields on both
    # drivers, and a field the project leaves unset falls back to the
    # driver's default. A selection that names no package leaves both
    # drivers' build paths alone; the haskell.nix half of that check
    # evaluates the hello plan, which `hello-haskell-nix` builds anyway.
    # Nothing here reads `builtins.outputOf`, which needs a Nix that
    # carries dynamic derivations.
    fine-grained-spec =
      let flagsFor = tweaks:
            import ../libs/nixpkgs/fine-grained/configure-flags.nix { inherit (pkgs) lib; } {
              name = "hello";
              inherit tweaks pkgs;
              ghc-options = [ "-Wall" ];
              ghc = pkgs.haskellPackages.ghc;
            };

          # Profiling on would warn, and the warning is not what this reads.
          quiet = {
            enableLibraryProfiling = false;
            doHaddock = false;
          };

          stated = flagsFor (quiet // { enableDeadCodeElimination = false; });

          fallback = flagsFor quiet;

          # Cabal hashes the flag assignment into the unit id, so a plan
          # must state the package's flags.
          assigned = flagsFor (quiet // { flags = { demo = true; webkit = false; }; });

          # The haskell.nix step takes the library component's own config,
          # so the stub carries every field it reads.
          component = {
            dontStrip = true;
            enableLibraryProfiling = false;
            enableProfiling = false;
            enableStatic = true;
            enableShared = true;
            enableExecutableDynamic = false;
            doCoverage = false;
            enableLibraryForGhci = true;
            enableDeadCodeElimination = false;
            profilingDetail = "default";
            configureFlags = [ "--extra-flag" ];
            ghcOptions = [ "-Wall" ];
          };

          statedHaskellNix =
            import ../libs/haskell-nix/fine-grained/configure-flags.nix { inherit (pkgs) lib; } {
              name = "hello";
              inherit component pkgs;
              ghc = pkgs.haskellPackages.ghc;
            };

          selected = driver: read: selection:
            read (eval [
              (import ../examples/hello/project.nix)
              { fine-grained = selection; }
            ]).config.${driver};

          nixpkgsDrv = selected "nixpkgs" (c: c.project.packages.hello.drvPath);

          haskellNixDrv = selected "haskell-nix"
            (c: c.project.hsPkgs.hello.components.exes.hello.drvPath);

          expected = {
            "profiling stated off" = hasInfix "--disable-library-profiling" stated;
            "documentation stated off" = ! hasInfix "-haddock" stated;
            "dead code stated off" = hasInfix "--disable-split-sections" stated;
            "ghc options carried" = hasInfix "--ghc-option=-Wall" stated;
            "dead code falls back" = hasInfix "--enable-split-sections" fallback;
            "flag stated on" = hasInfix "-fdemo" assigned;
            "flag stated off" = hasInfix "-f-webkit" assigned;
            "haskell.nix target stated" = hasPrefix "lib:hello" statedHaskellNix;
            "haskell.nix dead code stated off" = hasInfix "--disable-split-sections" statedHaskellNix;
            "haskell.nix ghc options carried" = hasInfix "--ghc-option=-Wall" statedHaskellNix;
            "haskell.nix configure flags carried" = hasInfix "--extra-flag" statedHaskellNix;
            "empty selection changes nothing" =
              nixpkgsDrv { enable = true; packages = []; }
              == nixpkgsDrv { enable = false; };
            "empty selection changes nothing on haskell.nix" =
              haskellNixDrv { enable = true; packages = []; }
              == haskellNixDrv { enable = false; };
          };

          failed = attrNames (filterAttrs (_: holds: ! holds) expected);

      in if failed == []
         then pkgs.runCommand "fine-grained-spec" {} "echo ok > $out"
         else throw "fine-grained: ${concatStringsSep ", " failed}";

    # ------------------------------------------------------------------------
    # cross-target-row-spec
    # ------------------------------------------------------------------------

    # A user-supplied cross-target row is a full target: its options exist,
    # the row registers for the bundle dispatch, node = false keeps Node.js
    # out of the shell, and the settings resolver tolerates a tool that no
    # layer of the settings trees declares.
    cross-target-row-spec =
      let row = {
            name = "probe";
            flag = "isProbe";
            matches = t: t.isAarch64 or false;
            selected = names: elem "aarch64-multiplatform" names;
            selectedText = "whether the selection names aarch64-multiplatform";
            optimizer = "probe-opt";
            optimize = "probe-optimize";
            runPath = "probe/run.nix";
            artifact = "binary";
            extension = "";
            examplePlatform = "aarch64-multiplatform";
            lead = "A probe target.";
            node = false;
            optimizer-fields = {
              enable = {
                type = pkgs.lib.types.bool;
                default = true;
                description = "Whether the probe runs.";
              };
            };
            optimize-defaultText = pkgs.lib.literalMD "the probe";
            mkOptimize = { pkgs, lib, settings }:
              { platform ? null, package ? null, exe ? null, binary }:
              pkgs.runCommand "probe-optimized" {
                resolved = builtins.toJSON (settings { inherit platform package exe; });
              } "echo $resolved > $out";
          };

          project = eval {
            name = "cross-target-row";
            src = ../examples/hello;
            imports = [ (import ../libs/cross/target-module.nix row) ];
            shell.crossPlatforms = ps: with ps; [ aarch64-multiplatform ];
            packages.hello = {};
            platforms.aarch64-multiplatform.bundle-optimizers.probe-opt.enable = false;
            platforms.aarch64-multiplatform.packages.hello.components.exes.hello.bundle-optimizers.probe-opt.enable = true;
          };

          cfg = project.config;

          resolvedWith = keys: builtins.fromJSON
            (cfg.probe-optimize (keys // { binary = "/probe"; })).resolved;

          resolvedBare = resolvedWith {};
          resolvedPackage = resolvedWith { package = "hello"; };
          resolvedPlatform = resolvedWith { platform = "aarch64-multiplatform"; };
          resolvedExe = resolvedWith {
            platform = "aarch64-multiplatform";
            package = "hello";
            exe = "hello";
          };

          failures =
            optional (!cfg.isProbe) "isProbe did not follow the selection"
            ++ optional (!(cfg.cross-targets ? probe)) "the row did not register"
            ++ optional (elem pkgs.nodejs-slim cfg.shell.buildInputs) "node = false still added nodejs"
            ++ optional (resolvedBare != { enable = true; })
                 "no names did not take the defaults: ${builtins.toJSON resolvedBare}"
            ++ optional (resolvedPackage != { enable = true; })
                 "a package entry without the tool did not state nothing: ${builtins.toJSON resolvedPackage}"
            ++ optional (resolvedPlatform != { enable = false; })
                 "the platform bundle-optimizers layer did not decide: ${builtins.toJSON resolvedPlatform}"
            ++ optional (resolvedExe != { enable = true; })
                 "the platform exe layer did not beat the whole-target layer: ${builtins.toJSON resolvedExe}";

      in if failures == []
         then pkgs.runCommand "cross-target-row-spec" {} "echo ok > $out"
         else throw (concatStringsSep "\n" failures);

    # ------------------------------------------------------------------------
    # every-option
    # ------------------------------------------------------------------------

    every-option = driver: pkgs.runCommand "every-option-${driver}" {
      drvPath = builtins.unsafeDiscardStringContext
        fixture.config.${driver}.project.shell.drvPath;
    } "echo $drvPath > $out";

in {

  # --------------------------------------------------------------------------
  # What the flake exposes
  # --------------------------------------------------------------------------

  inherit translation-totality compiler-spec bundle-optimizer-spec bundle-optimizers;
  inherit package-arguments-spec cross-target-row-spec fine-grained-spec;

  every-option-haskell-nix = every-option "haskell-nix";
  every-option-nixpkgs = every-option "nixpkgs";

  hello-nixpkgs = hello.config.nixpkgs.project.packages.hello;
  hello-haskell-nix = hello.config."haskell-nix".project.hsPkgs.hello.components.exes.hello;
}
