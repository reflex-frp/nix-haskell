# The cabal.project text and the pins its stanzas resolve through.
{ lib }:

with lib;
with (import ../../libs/common { inherit lib; });

{

  cabalProject = mkOption {
    type = types.nullOr types.lines;
    default = null;
    description = ''
      Content of the `cabal.project` file. `null` uses the file carried by
      the source.
    '';
    example = fenced-code ''
      packages: .
      tests: true
    '';
  };

  cabalProjectLocal = mkOption {
    type = types.nullOr types.lines;
    default = null;
    description = ''
      Content of the `cabal.project.local` file.
    '';
    example = "allow-newer: aeson:*";
  };

  cabalProjectFileName = mkOption {
    type = types.str;
    default = "cabal.project";
    description = ''
      Name of the cabal project file.
    '';
  };

  extraCabalProject = mkOption {
    type = types.listOf types.lines;
    default = [];
    description = ''
      Lines to append to `cabal.project`.
    '';
    example = [ "allow-newer: aeson:*" ];
  };

  inputMap = mkOption {
    type = types.attrs;
    default = {};
    description = ''
      Maps a url named in the cabal.project file to its source, so the
      source resolves without fetching. For a `source-repository-package`
      stanza, the driver checks the entry's `.rev` attribute against the
      stanza's `tag`.
    '';
    example = literalMD ''
      ```
        inputMap = {
          "{url}/{rev/ref}" = dep_src;
          "https://github.com/obsidiansystems/obelisk-oauth.git/a528c0542e9c30851e7c4542468a053fa5e482ef" = thunkSource ./dep/{thunk};
        };
      ```
    '';
  };

  sha256map = mkOption {
    type = types.nullOr (types.attrsOf (types.either types.str (types.attrsOf types.str)));
    default = null;
    description = ''
      Hashes for the sources that `source-repository-package` stanzas in
      the cabal.project name. An alternative to `--sha256` comments in
      that file.

      Keys are stanza `location` URLs. The value depends on the block:

      - for a `source-repository-package`, an attribute set from the
        stanza's `tag` to the sha256 of the source
      - for a `repository` block, the hash string itself
    '';
    example = literalMD ''
      ```
        sha256map = {
          "url"."rev/ref" = "hash"
          "https://github.com/jgm/pandoc-citeproc"."0.17" = "0dxx8cp2xndpw3jwiawch2dkrkp15mil7pyx7dvd810pwc22pm2q";
          "https://github.com/obsidiansystems/obelisk-oauth.git"."a528c0542e9c30851e7c4542468a053fa5e482ef" = lib.fakeHash;
        };
      ```
    '';
  };

}
