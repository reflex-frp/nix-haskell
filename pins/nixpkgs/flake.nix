# DO NOT HAND-EDIT THIS FILE
{
  inputs = {
    "upstream" = {
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36";
      type = "github";
    };
  };
  outputs = inputs: inputs."upstream".outputs // { src = inputs."upstream"; };
}
