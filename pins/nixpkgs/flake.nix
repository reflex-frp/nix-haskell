# DO NOT HAND-EDIT THIS FILE
{
  inputs = {
    "upstream" = {
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "6d65bfc1bcef2ef39a239d38e577e92a89fb0f07";
      type = "github";
    };
  };
  outputs = inputs: inputs."upstream".outputs // { src = inputs."upstream"; };
}
