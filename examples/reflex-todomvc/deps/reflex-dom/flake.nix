# DO NOT HAND-EDIT THIS FILE
{
  description = "nix-thunk packed thunk";
  inputs = {
    "src" = {
      flake = false;
      owner = "reflex-frp";
      repo = "reflex-dom";
      rev = "7193774e6beb8489f9f843448ade91548ab5f97c";
      type = "github";
    };
  };
  outputs = { self, src }: { inherit src; };
}
