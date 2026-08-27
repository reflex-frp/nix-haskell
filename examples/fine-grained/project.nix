{

  name = "fine-grained";
  src = ./.;

  # A plan holds one build way, and haddock reads sources rather than
  # compiled modules. Either one reads every module a second time.
  packages.fine-grained.enableLibraryProfiling = false;
  packages.fine-grained.doHaddock = false;

  fine-grained.enable = true;

}
