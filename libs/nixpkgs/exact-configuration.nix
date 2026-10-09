# Shell run before `Setup configure` that tells Cabal every direct
# dependency and every flag, so it resolves nothing of its own. The point is
# the bounds. A package whose cabal file excludes the compiler in hand still
# builds, even when the bound sits inside a conditional stanza, where
# `jailbreak` cannot reach it.
#
# The ids exist only once the builder has assembled its package database, so
# they are read there rather than computed in nix. Both databases are read:
# the one the builder made from this package's dependencies, and the
# compiler's own, where the boot libraries a cabal file names live.
#
# The registration files are read rather than `ghc-pkg dump`, which omits an
# entry whose own dependencies are absent from the database. They routinely
# are absent. The builder copies in the registrations of this package's
# dependencies, not of theirs. Cabal is content with that, while ghc-pkg
# calls it broken.
#
# The generated flags go ahead of the ones nix passed, and Cabal takes the last
# assignment of a flag, so a project's own `packages.<name>.flags` still decide.
#
# Example:
#
#   import ./exact-configuration.nix { ghc = "wasm32-wasi-ghc"; }
#   => shell which, before configuring jsaddle-wasm, makes
#
#        --exact-configuration
#        --dependency=base=base-4.22.0.0-inplace
#        --dependency=ghc-experimental=ghc-experimental-9.1401.0-inplace
#        ... one for every registration in either database ...
#        -feval-via-jsffi
#
#      and hands them to `Setup configure` in front of what nix passed
{ ghc }:

''
  # Every registration of either database, by the name and id it records. A
  # registration is written in aligned columns, and a value too long for its
  # column sits on the line below instead, which is where the id of a package
  # with a long name ends up.
  exactConfigurationIds() {
    for conf in "$1"/*.conf; do
      [ -f "$conf" ] || continue
      awk '
        /^name:/  { if (NF > 1) { name = $2; wrapped = "" } else wrapped = "name"; next }
        /^id:/    { if (NF > 1) { id = $2;   wrapped = "" } else wrapped = "id";   next }
        /^[ \t]/  { if (NF > 0 && wrapped != "") { if (wrapped == "name") name = $1; else id = $1; wrapped = "" }; next }
                  { wrapped = "" }
        END       { if (name != "" && id != "") printf " --dependency=%s=%s", name, id }
      ' "$conf"
    done
  }

  exactConfigurationDeps="$(exactConfigurationIds "$packageConfDir")$(exactConfigurationIds "$(${ghc} --print-libdir)/package.conf.d")"

  # Cabal assigns no flag itself when configuring exactly, so every flag the
  # package declares takes the value the cabal file declares for it, which is
  # True where it states none. A value may sit on the line below `Default:`,
  # which is where Cabal reads a field whose own line holds nothing.
  exactConfigurationFlags=$(awk '
    /^[Ff]lag[ \t]+/ { name = $2; value[name] = "True"; order[++n] = name; current = name; wrapped = 0; next }
    /^[^ \t]/        { current = ""; wrapped = 0 }
    current && /^[ \t]+[Dd]efault[ \t]*:/ {
      rest = $0
      sub(/^[ \t]+[Dd]efault[ \t]*:[ \t]*/, "", rest)
      if (rest != "")
        value[current] = (rest ~ /^[Ff]alse/) ? "False" : "True"
      wrapped = (rest == "")
      next
    }
    current && wrapped && NF > 0 {
      value[current] = ($1 ~ /^[Ff]alse/) ? "False" : "True"
      wrapped = 0
    }
    END {
      for (i = 1; i <= n; i++)
        printf " -f%s%s", (value[order[i]] == "False" ? "-" : ""), order[i]
    }' *.cabal)

  configureFlags="--exact-configuration$exactConfigurationDeps$exactConfigurationFlags $configureFlags"
''
