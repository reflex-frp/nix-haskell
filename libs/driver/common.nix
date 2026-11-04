# The common options mirrored under a driver's namespace. The result
# carries:
# - The declarations, hidden from the manual.
# - Seeds from the top-level values the project defined.
# - The common module's own config.
# - The pieces both drivers wire up the same way: the resolved compilers,
#   the namespaced config entries, and the driver-interface options.
#
# A driver definition overrides a seed, so a common option can be changed
# for one driver only. An option left entirely to its defaults gets no
# seed. It falls to the mirror's own declaration default, which evaluates
# against the mirror itself (`cfg`), so a default like name-from-src
# follows the driver's values.
#
# Example:
#
#   import ./common.nix {
#     inherit lib pkgs cfg;
#     driver = "nixpkgs";    # names the driver in error messages
#     topConfig = config;    # a project defining packages.reflex-dom.flags.webkit2gtk
#     topOptions = options;
#   }
#   => { options = <every common option, hidden from the manual>;
#        seeds = {
#          packages.reflex-dom.flags = {          # the whole field, since
#            _type = "override";                  # `flags` is not a submodule
#            priority = 1400;                     # to descend into
#            content = { webkit2gtk = false; };
#          };
#          src = ...;                             # the project's other
#          system = ...;                          # definitions, seeded the
#          shell = ...;                           # same way
#        };
#        config = <the common module's own config>;
#        mkDriverDefault = <a definition at priority 1450>;
#        compilers = <the `compiler` option resolved per platform>;
#        mirror-config = <namespace and default compiler to config entries>;
#        interface = <per-driver payloads to the three shared options>;
#      }
#
#   `packages.reflex-dom.patches` gets no seed, nor does any other field the
#   project left alone, so a driver default still reaches it. A driver's own
#   `nixpkgs.packages.reflex-dom.flags` beats the seed. That is how a common
#   option changes for one driver only.
{ lib, pkgs, topConfig, topOptions, cfg, driver }:

with lib;
with (import ../common { inherit lib; });

let # The mirror gets `topConfig` too. An option settled once for the whole
    # project, rather than per driver, is read from `topConfig`, even though
    # the mirror also carries a declaration of it.
    commonModule = import ../../modules/common {
      inherit lib pkgs topConfig;
      config = cfg;
    };

    # ------------------------------------------------------------------------
    # Seeds
    # ------------------------------------------------------------------------

    # The seed rules:
    # - Seeds sit at 1400, between mkDefault (1000) and declaration defaults
    #   (1500). They are weaker than any definition and stronger than the
    #   mirror's own declaration defaults. mkOptionDefault cannot express
    #   this, because declaration defaults materialize at its priority and
    #   equal-priority definitions conflict.
    # - Only what the project defined is seeded, down to the field. A seed
    #   lands on a path exactly when some top-level definition mentions it.
    #   A driver default (mkDriverDefault, 1450) therefore still applies to
    #   every field the project left alone, however deeply nested, and yields
    #   to any field it did set. Seeding the whole of a submodule-typed
    #   option would defeat driver defaults on all of its fields as soon as
    #   one of them was defined.
    # - Declaration defaults do not count as definitions. The module system
    #   injects them at mkOptionDefault priority (1500), so a definition is
    #   one that beats 1500.
    # - Descent follows the declared sub-options, not the values, so a seed
    #   only lands where an option exists to receive it. Read-only
    #   sub-options are left out, because a read-only option set twice is an
    #   error.
    # - Reading any mirror option forces the definition priorities of every
    #   settable common option, so top-level common options must not be gated
    #   on driver config.
    seeds =
      let seed = mkOverride 1400;

          settableOptions = filterAttrs (_: is-settable) commonModule.options;

          declarationDefaultPrio = (mkOptionDefault null).priority;

          definedOptions =
            filterAttrs
              (name: _: topOptions.${name}.highestPrio < declarationDefaultPrio)
              settableOptions;

          # A submodule's own settable options, which are what a definition of
          # it can name.
          subOptions = type:
            filterAttrs (name: option: name != "_module" && is-settable option)
              (type.getSubOptions []);

          # The definitions that can carry a path below them. A derivation is an
          # attrset too, and is a value rather than a path.
          pathDefs = defs: filter (def: isAttrs def && ! isDerivation def) defs;

          namedIn = defs: name: any (def: def ? ${name}) (pathDefs defs);

          defsUnder = defs: name: catAttrs name (pathDefs defs);

          seedOption = option: defs: value:
            let kind = submodule-type option.type;
            in  if kind.isSubmodule
                  then seedFields (subOptions option.type) defs value
                else if kind.isAttrsOfSubmodule
                  then
                    let keys = filter (namedIn defs) (attrNames value);
                    in genAttrs keys
                         (key: seedFields (subOptions kind.elemType) (defsUnder defs key) value.${key})
                else seed value;

          seedFields = fields: defs: value:
            mapAttrs
              (name: option: seedOption option (defsUnder defs name) value.${name})
              (filterAttrs (name: _: namedIn defs name) fields);

      in mapAttrs
           (name: option: seedOption option topOptions.${name}.definitions topConfig.${name})
           definedOptions;

    # A default a driver states for itself, weaker than the seeds above, so it
    # applies only where the project said nothing.
    mkDriverDefault = import ./priority.nix { inherit lib; };

    # The `compiler` option resolved per platform, from the mirror's values.
    compilers = import ../compiler { inherit lib; } {
      compiler = cfg.compiler;
      system = cfg.system;
      inherit driver;
    };

in {

  # --------------------------------------------------------------------------
  # What the mirror hands its driver
  # --------------------------------------------------------------------------

  options = mapAttrs (_: option: option // { visible = false; }) commonModule.options;

  inherit seeds;

  inherit (commonModule) config;

  inherit mkDriverDefault compilers;

  # --------------------------------------------------------------------------
  # Mirror config
  # --------------------------------------------------------------------------

  # The driver's shared `config` entries, keyed under its namespace: the
  # seeds, the common module's own config, and the driver's own default
  # compiler name. The guard on the name: a compiler package names itself
  # through its version, and an unguarded default would beat that derived
  # name instead of yielding to it.
  mirror-config = { namespace, defaultCompiler }: [
    { ${namespace} = seeds; }
    { ${namespace} = commonModule.config; }
    { ${namespace}.compiler.name =
        mkIf (cfg.compiler.package == null) (mkDriverDefault defaultCompiler);
    }
  ];

  # --------------------------------------------------------------------------
  # Driver interface
  # --------------------------------------------------------------------------

  # The three options both drivers answer to by the same name. The
  # descriptions are the cross-driver interface spec, stated once. A driver
  # passes its own fallbacks, defaults and defaultTexts. `extraDescription`
  # appends a driver's own paragraph.
  interface = { compiler-version, cross-compiler, cross-exe }: {

    compiler-version = mkOption {
      type = types.str;
      default =
        if compilers.native.version != null
        then compilers.native.version
        else compiler-version.fallback;
      inherit (compiler-version) defaultText;
      description = ''
        The version of the compiler this driver builds with. Both drivers
        answer to the same name, and each answers for itself. They mirror
        `compiler` separately and fall back to different compilers of
        their own. A project that wants to know what it builds against
        asks the driver:

        ```
        config.<driver>.compiler-version
        ```
      '';
    };

    cross-compiler = function-option {
      inherit (cross-compiler) default defaultText;
      description = ''
        The compiler this driver builds a cross target with, by
        `pkgs.pkgsCross` name. Both drivers answer to the same name. A
        step that needs the compiler an artifact was built with, as
        `wasm-jsffi` does, asks the same way whichever driver built the
        artifact:

        ```
        config.<driver>.cross-compiler "wasi32"
        ```
      '';
    };

    cross-exe = function-option {
      inherit (cross-exe) default defaultText;
      description = ''
        What this driver builds an executable into, for one cross target.
        Both drivers answer to the same name. The answer carries the
        executable at `bin/<exe>`. A wasm target's binary sits at
        `bin/<exe>.wasm`, and a javascript target's linked directory at
        `bin/<exe>.jsexe`. `bundles` optimizes this result.
      '' + cross-exe.extraDescription or "";
    };

  };

}
