# DO NOT HAND-EDIT THIS FILE
{
  inputs = {
    "upstream" = {
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "6f06d204d8f2d8761d9da78778745974a3216381";
      type = "github";
    };
  };
  outputs = inputs: inputs."upstream".outputs // { src = inputs."upstream"; };
}
