# The `compiler` option: the fields of a compiler entry, shared by the
# native compiler and the per-platform ones.
{ lib }:

with lib;
with (import ../../libs/prelude { inherit lib; });

let toolchainTools = import ../../libs/compiler/toolchain-tools.nix;

    toolOption = tool: nameValuePair tool.name (mkOption {
      type = types.nullOr types.str;
      default = null;
      inherit (tool) example;
      description = "The ${tool.noun}'s name in the toolchain's `bin`, passed to cabal as `--with-${tool.flag}`.\n";
    });

    # The defaultText of a compiler field that is read off `package` when
    # the option is unset.
    fromPackage = field: fallback:
      literalMD "`null`: the `${field}` of `package`, else ${fallback}\n";

    # Fields only one driver reads sit under that driver's own key.
    #
    # Every default is literal, `null` or empty. What a field falls back to
    # depends on the driver (`name`) or on the package (the rest), so each
    # driver resolves it for itself, taking in order:
    #
    # 1. the field
    # 2. the attribute the package carries
    # 3. a neutral value
    #
    # A default resolved here could not do that job. A driver's mirror seeds
    # every field of a submodule option as soon as one of them is defined,
    # which would freeze a single answer into both drivers.
    compilerEntry = {

      # ----------------------------------------------------------------------
      # Naming and version
      # ----------------------------------------------------------------------

      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        defaultText = literalMD ''
          `null`: the driver's own compiler, `ghc914` for haskell.nix and
          `ghc912` for nixpkgs, where no stackage snapshot covers 9.14 yet
        '';
        example = "ghc912";
        description = ''
          The compiler's name in the driver's package sets
          (`haskell-nix.compiler.<name>`, `pkgs.haskell.packages.<name>`),
          and the name the driver pins the project's packages under. With
          `package` set, the name selects the set whose compiler the package
          replaces. Set it only when the driver does not know the name
          derived from the version.
        '';
      };

      package = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = ''
          A compiler used directly instead of one from the driver's package
          sets:

          - a bindist
          - an out-of-tree cross compiler
          - a locally built GHC

          The sibling fields are spliced onto the package. Both drivers
          read them off the compiler itself, and a bindist generally
          carries none of them.
        '';
        example = fenced-code ''pkgs.haskell.compiler.ghc912'';
      };

      version = mkOption {
        type = types.nullOr types.str;
        default = null;
        defaultText = fromPackage "version" "the version in its name";
        example = "9.12.4.20260731";
        description = ''
          The compiler's version. Both drivers read it off the compiler, for
          paths and for `impl(ghc >= ...)` conditionals.

          Some builds cannot use the compiler package itself:

          - the nixpkgs package set the driver builds the project against
          - haskell.nix's shell tools

          These builds use the driver's stock compiler of the same
          major.minor.patch instead.

          Set this for a nightly bindist. A nightly's name carries only its
          series.
        '';
      };

      targetPrefix = mkOption {
        type = types.nullOr types.str;
        default = null;
        defaultText = fromPackage "targetPrefix" "the empty string";
        example = "wasm32-wasi-";
        description = ''
          The prefix on the compiler's executables. Both drivers invoke
          every tool by its prefixed name.
        '';
      };

      enableShared = mkOption {
        type = types.nullOr types.bool;
        default = null;
        defaultText = fromPackage "enableShared" "`true`";
        description = ''
          Whether the compiler can build shared libraries. Each driver reads
          it:

          - haskell.nix sets every component's `shared:` flag from it
          - nixpkgs builds a cross package set non-static, with shared
            libraries instead of static ones

          GHC's wasm backend needs it, because its Template Haskell
          interpreter loads shared objects.
        '';
      };

      # ----------------------------------------------------------------------
      # Toolchain
      # ----------------------------------------------------------------------

      toolchain = mkOption {
        default = {};
        description = ''
          The C toolchain the compiler was configured with, when that is not
          the one the surrounding package set supplies. The drivers point
          everything built with the compiler back at it, since `Setup
          configure`'s foreign-dependency checks otherwise look in the wrong
          sysroot. Each driver does that its own way:

          - haskell.nix passes it as every package's configure flags
          - nixpkgs makes it the cross package set's toolchain outright
        '';
        example = fenced-code ''{ package = wasi-sdk; cc = "clang"; ar = "llvm-ar"; }'';
        type = types.submodule {
          options = {

            package = mkOption {
              type = types.nullOr types.package;
              default = null;
              description = ''
                The toolchain itself. The nixpkgs driver also makes it a
                setup dependency of every package, so that a setup hook
                exporting `CC`, `AR` and the other tool variables is
                honored.
              '';
            };

            extra = mkOption {
              type = types.attrsOf types.str;
              default = {};
              example = { pkg-config = "wasm32-wasi-pkg-config"; };
              description = ''
                Extra `--with-<key>` tools of the toolchain. The key is
                cabal's name for the tool, the value its executable name in
                the toolchain package's `bin`. The driver emits them after
                the fixed tools. Cabal takes a flag's last occurrence, so
                an entry can also override one of them.
              '';
            };

          } // listToAttrs (map toolOption toolchainTools);
        };
      };

      # ----------------------------------------------------------------------
      # Details one driver reads
      # ----------------------------------------------------------------------

      haskell-nix = mkOption {
        default = {};
        description = ''
          Compiler details only the haskell.nix driver reads.
        '';
        type = types.submodule {
          options = {

            libDir = mkOption {
              type = types.nullOr types.str;
              default = null;
              defaultText = fromPackage "libDir" "the path haskell.nix derives from the version";
              example = "lib";
              description = ''
                The compiler's library directory, relative to its store path,
                where the driver looks for the package database and
                `settings`. A relocatable bindist keeps them directly under
                `lib`, rather than under the `lib/<prefix>ghc-<version>/lib`
                of a version-named install.
              '';
            };

            extraNonReinstallablePkgs = mkOption {
              type = types.listOf types.str;
              default = [];
              example = [ "system-cxx-std-lib" ];
              description = ''
                Packages to copy from the compiler's database, with the
                packages they need. Name a package that only a plan package
                needs, such as `system-cxx-std-lib` for a simdutf `text`.
              '';
            };

          };
        };
      };

      nixpkgs = mkOption {
        default = {};
        description = ''
          Compiler details only the nixpkgs driver reads.
        '';
        type = types.submodule {
          options = {

            haskellCompilerName = mkOption {
              type = types.nullOr types.str;
              default = null;
              defaultText = fromPackage "haskellCompilerName" "`ghc-<version>`";
              example = "ghc-9.12.4.20260731";
              description = ''
                The compiler's cabal name. The driver names the package
                database directories of everything it builds after this
                name, and passes the name to cabal2nix as `--compiler`.
              '';
            };

            enableExternalInterpreter = mkOption {
              type = types.nullOr types.bool;
              default = null;
              defaultText = literalMD ''
                `null`: nixpkgs' own choice, which is to use the external
                interpreter whenever it is cross-compiling and an emulator
                exists for the target
              '';
              description = ''
                Whether to run Template Haskell splices through nixpkgs'
                external interpreter, which proxies them to the target over
                a socket. Set `false` when:

                - the compiler runs splices itself, such as GHC's wasm
                  backend
                - the target has no sockets to proxy over
              '';
            };

          };
        };
      };

    };

in {

  # --------------------------------------------------------------------------
  # The compiler option
  # --------------------------------------------------------------------------

  compiler = mkOption {
    default = {};
    description = ''
      The GHC to build with:

      - `name` selects one of the driver's own compilers
      - `package` supplies one from outside them, and the sibling fields
        are the attributes the drivers read off a compiler
      - `platforms` gives cross targets their own compiler and toolchain

      A platform without an entry uses the fields above it.

      Describe such a compiler once. The modules under
      `nix-haskell-compilers` are ready-made entries for compilers
      distributed outside the drivers' package sets.
    '';
    example = literalExpression ''
      {
        name = "ghc912";

        # a bindist for the wasm target, with the toolchain it was built
        # with, as `nix-haskell-compilers/ghc-wasm-meta` supplies it
        platforms.wasi32 = {
          package = wasm-ghc;
          version = "9.12.4.20260731";
          targetPrefix = "wasm32-wasi-";
          enableShared = true;
          haskell-nix.libDir = "lib";
          haskell-nix.extraNonReinstallablePkgs = [ "system-cxx-std-lib" ];
          nixpkgs.enableExternalInterpreter = false;
          toolchain = {
            package = wasi-sdk;
            cc = "wasm32-wasi-clang";
            ar = "llvm-ar";
            ld = "wasm-ld";
            strip = "llvm-strip";
          };
        };
      }
    '';
    type = types.submodule {
      options = compilerEntry // {

        # A mirror seeds submodule fields only one level deep, so a
        # per-driver definition under `compiler.platforms` replaces the
        # whole table for that driver.
        platforms = mkOption {
          type = types.attrsOf (types.submodule { options = compilerEntry; });
          default = {};
          description = ''
            Per-platform compilers, keyed by `pkgsCross` platform name
            (the keys of `shell.crossPlatforms` and `projectCross`). An
            entry has the same fields as the compiler above. A field an
            entry leaves unset resolves from that entry's own `package`,
            not from the compiler above. A per-driver definition anywhere
            under `compiler.platforms` replaces the whole table for that
            driver.
          '';
          example = fenced-code ''{ wasi32 = { package = ghc-wasm-bindist; haskell-nix.libDir = "lib"; }; }'';
        };

      };
    };
  };

}
