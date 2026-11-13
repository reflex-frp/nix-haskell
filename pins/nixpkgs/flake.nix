# DO NOT HAND-EDIT THIS FILE
{
  inputs = {
    "upstream" = {
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "ac588ef1c914865dad517b337ea0eb9694a4021c";
      type = "github";
    };
  };
  outputs = inputs: inputs."upstream".outputs // { src = inputs."upstream"; };
}
