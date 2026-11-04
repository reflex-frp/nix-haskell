# Approximate evaluator for the `condition` field of
# source-repository-packages: cabal conditional syntax, evaluated against a
# platform. It handles os(..), arch(..), !, &&, || and parentheses.
# Anything it cannot evaluate (impl(..), flag(..)) is assumed true, with a
# warning.
#
# `hostMap` is haskell.nix's platform mapping (lib/host-map.nix applied to
# the target stdenv): the cabal names of the platform.
#
# Example:
#
#   holds = import ./condition.nix {
#     inherit lib;
#     hostMap = { os = "Linux"; arch = "X86_64"; };
#   };
#
#   holds "!arch(javascript) && os(linux)"   => true
#   holds "arch(javascript)"                 => false
#   holds "impl(ghc >= 9.6)"                 => true, with a warning: a
#                                               condition it cannot evaluate is
#                                               assumed to hold
{ lib, hostMap }:

with (import ../common { inherit lib; });

let prefix = message-prefix { driver = "nixpkgs"; };

    inherit (lib) toLower warn any all hasPrefix removePrefix stringToCharacters trim;

    # Split `s` on the two-character operator `sep` at parenthesis depth 0.
    splitTop = sep: s:
      let chars = stringToCharacters s;
          n = builtins.length chars;
          op = builtins.substring 0 1 sep;
          go = i: depth: start: acc:
            if i >= n
            then acc ++ [ (builtins.substring start (n - start) s) ]
            else
              let c = builtins.elemAt chars i;
              in if c == "(" then go (i + 1) (depth + 1) start acc
                 else if c == ")" then go (i + 1) (depth - 1) start acc
                 else if depth == 0 && c == op && i + 1 < n && builtins.elemAt chars (i + 1) == op
                 then go (i + 2) depth (i + 2) (acc ++ [ (builtins.substring start (i - start) s) ])
                 else go (i + 1) depth start acc;
      in go 0 0 0 [];

    osHolds = o:
      let os = toLower o;
      in os == toLower hostMap.os
         # cabal's name for darwin is osx
         || (os == "darwin" && toLower hostMap.os == "osx");

    archHolds = a: toLower a == toLower hostMap.arch;

    evalAtom = s:
      let t = trim s;

          parsedCall = builtins.match "(os|arch|impl|flag)[[:space:]]*\\(([^)]*)\\)" t;

          call =
            let fn = builtins.head parsedCall;
                arg = trim (builtins.elemAt parsedCall 1);
            in if fn == "os"
               then osHolds arg
               else if fn == "arch"
               then archHolds arg
               else warn (prefix "${fn}(${arg}) source-repository-package conditions are not evaluated; assuming true") true;

      in if t == ""
         then true
         else if hasPrefix "!" t
         then ! (evalAtom (removePrefix "!" t))
         else if hasPrefix "(" t
         then evalExpr (builtins.substring 1 (builtins.stringLength t - 2) t)
         else if parsedCall == null
         then warn (prefix "cannot evaluate the source-repository-package condition '${t}'; assuming true") true
         else call;

    splitEval = op: combine: sub: s:
      let parts = splitTop op (trim s);
      in if builtins.length parts > 1
         then combine sub parts
         else sub s;

    evalAnd = splitEval "&&" all evalAtom;

    evalExpr = splitEval "||" any evalAnd;

in evalExpr
