# DO NOT HAND-EDIT THIS FILE
{
  inputs = {
    "upstream" = {
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "7dcdd87373d72e7a2173e4db02e20d3d7f495cfd";
      type = "github";
    };
  };
  outputs = inputs: inputs."upstream".outputs // { src = inputs."upstream"; };
}
