# A cross package set built with a compiler's own C toolchain instead of
# the one nixpkgs would assemble for the platform. The toolchain stands in
# for the cross `cc`. nixpkgs reads only that value's metadata, and the
# compiler and the toolchain's setup hook drive the compilation, so a
# toolchain that is not shaped like a wrapper still works there. Every
# Haskell package then runs the hook and is pointed at the toolchain's
# tools.
#
# Shared libraries are load bearing rather than a preference. A compiler
# whose Template Haskell interpreter loads shared objects, as GHC's wasm
# backend does, cannot work in a static set. A static cross set also sends
# nixpkgs to its socket-based external interpreter, which a target without
# sockets cannot run.
#
# Example:
#
#   import ./cross-pkgs.nix {
#     inherit lib;
#     pkgs = config.nixpkgs.pkgs;
#     system = "x86_64-linux";
#     platform = "wasi32";
#     compiler = <resolved entry with a toolchain>;
#     defaults = { jailbreak = true; haddock = false; profiling = false; };
#   }
#   => <a wasi32 package set whose Haskell packages build with the bindist>
{ lib, pkgs, system, platform, compiler, defaults }:

let toolchain = compiler.toolchain.package;

    inherit (compiler) targetPrefix enableShared;

    crossSystem = lib.systems.elaborate lib.systems.examples.${platform}
      // lib.optionalAttrs enableShared { isStatic = false; };

    # The `pname` and `version` on the libc are what nixpkgs expects to find
    # on one.
    libcStandIn = toolchain.overrideAttrs (attrs: {
      pname = attrs.name;
      version = "unstable";
    });

    bintoolsStandIn = toolchain // {
      inherit targetPrefix;
      bintools = toolchain // { inherit targetPrefix; };
    };

    ccStandIn = toolchain // {
      isGNU = false;
      isClang = true;
      libc = libcStandIn;
      inherit targetPrefix;
      bintools = bintoolsStandIn;
    };

    # Only the metadata nixpkgs consults about a cross compiler: what kind it
    # is, where its libc lives, and the prefix its tools carry.
    crossStdenv = { buildPackages, baseStdenv }:
      buildPackages.stdenvNoCC.override {
        inherit (baseStdenv) buildPlatform hostPlatform targetPlatform;
        cc = ccStandIn;
      };

    # Everything the set builds is configured against the compiler's toolchain
    # and runs its setup hook. What is relaxed for the whole set comes in as
    # `defaults`; a project's own `packages.<name>` settings still win, because
    # the driver layers them on after this.
    crossArgs = args: args // {
      configureFlags = (args.configureFlags or []) ++ compiler.toolchainFlags;
      setupHaskellDepends = (args.setupHaskellDepends or []) ++ [ toolchain ];
      preBuild = ''
        ${args.preBuild or ""}
        export NIX_CC=$CC
      '';
      enableSharedLibraries = enableShared;
      enableStaticLibraries = ! enableShared;
      enableLibraryProfiling = defaults.profiling;
      doHaddock = defaults.haddock;
      jailbreak = defaults.jailbreak;
      # nothing here can run what it builds
      doCheck = false;
      doBenchmark = false;
    } // lib.optionalAttrs (compiler.enableExternalInterpreter != null) {
      inherit (compiler) enableExternalInterpreter;
    };

    renamedForTarget = drv: drv.overrideAttrs (attrs: {
      name = "${attrs.pname}-${targetPrefix}${attrs.version}";
      preSetupCompilerEnvironment = ''
        export CC_FOR_BUILD=$CC
      '';
    });

    crossMkDerivation = hprev: args: renamedForTarget (hprev.mkDerivation (crossArgs args));

    haskellPackageOverrides = hfinal: hprev: {
      mkDerivation = crossMkDerivation hprev;
    };

    haskellOverlay = final: prev: {
      haskell = prev.haskell // {
        packageOverrides = lib.composeManyExtensions [
          prev.haskell.packageOverrides
          haskellPackageOverrides
        ];
      };
    };

in import ./reimport.nix pkgs {
  inherit system crossSystem;
  config.replaceCrossStdenv = crossStdenv;
  crossOverlays = [ haskellOverlay ];
}
