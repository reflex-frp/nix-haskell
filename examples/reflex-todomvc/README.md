# TodoMVC in Reflex

All of the code lives in `src/Reflex/TodoMVC.hs`.
`static/style.css` is embedded into the application.

## Build Instructions

The driver is the first `-A` attribute (`haskell-nix` or `nixpkgs`):

```bash
nix-build -A haskell-nix.projectCross.wasi32.hsPkgs.reflex-todomvc.components.exes.reflex-todomvc
```

```bash
nix-build -A haskell-nix.projectCross.ghcjs.hsPkgs.reflex-todomvc.components.exes.reflex-todomvc
```

```bash
nix-build -A nixpkgs.packages.reflex-todomvc
```

The wasm page loads two files that are not in the repository: the binary
through the optimizer, and the `ghc_wasm_jsffi.js` that GHC generates from
it. Link both beside `wasm.js`, from the same bundle row so they match:

```bash
nix-build release.nix -A bundle.haskell-nix.ghc914.wasi32.optimized -o reflex-todomvc.wasm
nix-build release.nix -A bundle.haskell-nix.ghc914.wasi32.jsffi -o ghc_wasm_jsffi.js
```

For a `-wasm-meta` build, use the `bundle.wasm-meta` rows with `ghc912`.

The GHCJS page loads `all.js` from the optimized `.jsexe` the same way:

```bash
nix-build release.nix -A bundle.haskell-nix.ghc914.ghcjs.optimized -o reflex-todomvc.jsexe
```

Then open `index-wasm.html` (wasm) or `index-js.html` (GHCJS) in your
browser!

### With an out-of-tree compiler

The `-wasm-meta` attributes build the wasm target with the GHC 9.12 bindist of
the `ghc-wasm-meta` pin instead of the drivers' own compilers:

```bash
nix-build -A haskell-nix-wasm-meta.projectCross.wasi32.hsPkgs.reflex-todomvc.components.exes.reflex-todomvc
```

```bash
nix-build -A nixpkgs-wasm-meta.projectCross.wasi32.packages.reflex-todomvc
```

or through the flake: `nix build .#haskell-nix-wasm-meta` /
`nix build .#nixpkgs-wasm-meta`.

`default.nix` takes the compiler from `wasm-meta.nix`, which imports
`nix-haskell-compilers/ghc-wasm-meta`. That module describes the bindist
and the wasi-sdk it was configured with. Each driver handles a compiler
like that on its own. The project only assigns a flag: `project.nix` sets
the flags of a `!arch(wasm32)` stanza for the nixpkgs driver, which cannot
read the stanza. The warp backend those flags select brings in C libraries
that nixpkgs cannot cross-compile to wasi.

## Shell

The same `-A` choice selects the shell's driver:

```bash
nix-shell -A haskell-nix
nix-shell -A nixpkgs
```

or through the flake: `nix develop` / `nix develop .#nixpkgs`.
