# This driver's payloads for the common interface options: the resolved
# compiler version, and where a cross platform's compiler and executables
# come from.
{ lib, cfg }:

with lib;
with (import ../../libs/common { inherit lib; });

{

  compiler-version = {
    fallback = cfg.haskellPackages.ghc.version;
    defaultText = literalMD ''
      the version `compiler.version` states, or the one carried by the
      compiler the driver resolves: the package a project brought, or the
      `ghc` of the package set it selected
    '';
  };

  cross-compiler = {
    default = platform: cfg.project.projectCross.${platform}.haskellPackages.ghc;
    defaultText = fenced-code ''platform: config.nixpkgs.project.projectCross.<platform>.haskellPackages.ghc'';
  };

  cross-exe = {
    default = { platform, package, exe }:
      cfg.project.projectCross.${platform}.packages.${package};
    defaultText = fenced-code ''
      { platform, package, exe }:
        config.nixpkgs.project.projectCross.<platform>.packages.<package>
    '';
    extraDescription = ''

      This driver builds one derivation per package, so the executable's
      own name does not affect the lookup. The function takes it only to
      keep the one interface both drivers answer to.
    '';
  };

}
