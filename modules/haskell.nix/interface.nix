# This driver's payloads for the common interface options: the resolved
# compiler version, and where a cross platform's compiler and executables
# come from.
{ lib, cfg, compiler }:

with lib;
with (import ../../libs/common { inherit lib; });

{

  compiler-version = {
    # haskell.nix keys its compilers by exact version, and resolves the
    # name a project writes to one of them.
    fallback = cfg.haskell-nix.compiler.${cfg.haskell-nix.resolve-compiler-name compiler.name}.version;
    defaultText = literalMD ''
      the version `compiler.version` states, or the one carried by the
      compiler the driver resolves: the package a project brought, or the
      one haskell.nix has under that name
    '';
  };

  cross-compiler = {
    default = platform: cfg.project.projectCross.${platform}.pkg-set.config.ghc.package;
    defaultText = fenced-code ''
      platform:
        config."haskell-nix".project.projectCross.<platform>.pkg-set.config.ghc.package
    '';
  };

  cross-exe = {
    default = { platform, package, exe }:
      cfg.project.projectCross.${platform}.hsPkgs.${package}.components.exes.${exe};
    defaultText = fenced-code ''
      { platform, package, exe }:
        config."haskell-nix".project.projectCross.<platform>
          .hsPkgs.<package>.components.exes.<exe>
    '';
  };

}
