# Names of the user-settable options in an evaluated options tree. The list
# excludes internal, read-only and hidden options, and the namespaces listed
# in `excludes`. Sub-options of submodule-typed options appear one level
# deep. A plain namespace of options counts as a single name.
#
# Example:
#
#   import ./option-names.nix {
#     inherit lib;
#     excludes = [ "haskell-nix" ];
#     options = {            # an evaluated `options` tree, containing e.g.
#       src = ...;           #   an ordinary option
#       src-cleaned = ...;   #   a readOnly option
#       shell = ...;         #   a submodule-typed option
#       packages = ...;      #   an attrsOf-submodule option
#       optimizations = ...; #   a plain namespace of options
#       haskell-nix = ...;   #   an excluded namespace
#     };
#   }
#   => [ "optimizations" "packages.*.flags" ... "packages.*.src"
#        "shell.buildInputs" ... "shell.withHoogle" "src" ]

{ lib, options, excludes ? [] }:

with lib;
with (import ../common { inherit lib; });

let subNames = prefix: opts:
      let visibleOptions = filterAttrs (n: o: n != "_module" && isOption o && is-visible o) opts;
          visibleOptionNames = attrNames visibleOptions;
      in map (n: prefix + n) visibleOptionNames;

    expand = name: option:
      let kind = submodule-type option.type;
      in  if kind.isSubmodule
            then subNames "${name}." (option.type.getSubOptions [])
          else if kind.isAttrsOfSubmodule
            then subNames "${name}.*." (kind.elemType.getSubOptions [])
          else [ name ];

    includedOptions = filterAttrs
      (name: _: name != "_module" && !(elem name excludes))
      options;

    optionNames = name: option:
      if isOption option
      then optionals (is-visible option) (expand name option)
      else [ name ];

in sort lessThan (concatLists (mapAttrsToList optionNames includedOptions))
