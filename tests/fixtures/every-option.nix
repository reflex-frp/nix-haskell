# A project that sets every common option to a non-trivial value, so the
# checks push real values through both drivers' full translation.
{ pkgs, ... }:

{

  name = "every-option";
  src = ./every-option;
  clean-src = true;
  clean-src-ignore-files = [ "/.gitignore" "/nested/.gitignore" ];
  clean-src-patterns = ''
    dist-newstyle
  '';
  compiler.name = "ghc912";

  ghcOptions = [ "-O1" ];

  cabalProject = ''
    packages: .
  '';
  cabalProjectLocal = ''
    -- every-option cabal.project.local
  '';
  cabalProjectFileName = "cabal.project";
  extraCabalProject = [ "-- appended by every-option" ];
  inputMap."https://example.invalid/dep-a" = ./dep-a;
  sha256map."https://example.invalid/dep-a"."main" =
    "0000000000000000000000000000000000000000000000000000";

  packages = {
    every-option = {
      flags.demo = true;
      patches = [ ./every-option.patch ];
      ghcOptions = [ "-Wall" ];
      configureFlags = [ "--enable-optimization" ];
      setupBuildFlags = [ "-v1" ];
      setupHaddockFlags = [ "--verbose=1" ];
      doCheck = false;
      doHaddock = false;
      doCoverage = false;
      doHoogle = false;
      doHyperlinkSource = false;
      doQuickjump = false;
      dontStrip = false;
      enableDeadCodeElimination = false;
      enableLibraryProfiling = false;
      enableProfiling = false;
      profilingDetail = "toplevel-functions";
      enableShared = true;
      enableStatic = true;
      enableSeparateDataOutput = false;
      enableLibraryForGhci = false;
      hardeningDisable = [ "format" ];
      previousIntermediates = "/var/empty";
      preUnpack = "echo every-option pre-unpack";
      postUnpack = "echo every-option post-unpack";
      prePatch = "echo every-option pre-patch";
      postPatch = "echo every-option post-patch";
      preConfigure = "echo every-option pre-configure";
      postConfigure = "echo every-option post-configure";
      preBuild = "echo every-option pre-build";
      postBuild = "echo every-option post-build";
      preCheck = "echo every-option pre-check";
      postCheck = "echo every-option post-check";
      preHaddock = "echo every-option pre-haddock";
      postHaddock = "echo every-option post-haddock";
      preInstall = "echo every-option pre-install";
      postInstall = "echo every-option post-install";
      src = ./every-option;
      wasm-opt.level = "3";
      closure-compiler.level = "WHITESPACE_ONLY";
      components.exes.every-option.wasm-opt.extraFlags = [ "--strip-dwarf" ];
      components.exes.every-option.closure-compiler.externs = [ ./every-option-externs.js ];
    };
    absent-package.doCheck = false;
  };

  shell = {
    packages = ps: with ps; [ every-option "absent-package" ];
    tools.cabal = "latest";
    buildInputs = [ pkgs.jq ];
    nativeBuildInputs = [ pkgs.gnused ];
    shellHook = "echo every-option";
    withHoogle = false;
    crossPlatforms = _: [];
  };

  source-repository-packages = {
    dep-a = {
      src = ./dep-a;
      condition = "!arch(javascript)";
    };
  };

  hackage-overlays = [
    {
      name = "dep-b";
      version = "0.1.0.0";
      src = ./dep-b;
    }
  ];

  optimizations.expose-all-unfoldings = true;

  wasm-opt = {
    enable = true;
    level = "z";
    extraFlags = [ "--converge" ];
  };
  closure-compiler = {
    enable = true;
    level = "SIMPLE";
    externs = [ ./every-option-externs.js ];
    extraFlags = [ "--warning_level QUIET" ];
  };

  platforms.wasi32 = {
    wasm-opt.level = "s";
    packages.every-option.wasm-opt.extraFlags = [ "--low-memory-unused" ];
    packages.every-option.components.exes.every-option.wasm-opt.level = "4";
  };

  haskell-nix.packages.every-option.doQuickjump = true;
  nixpkgs.packages.every-option.doHoogle = true;

  # A selection that names no package. The fixture then holds these options
  # without a Nix that carries dynamic derivations.
  fine-grained = {
    enable = true;
    packages = [];
  };

  inputs.every-option-fixture = ./dep-a;

  isGhcjs = false;
  isWasm = false;

}
