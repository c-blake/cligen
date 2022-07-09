#!/bin/sh
# Some users complained about object file size bloat.  Concrete e.g.s both make
# such complaints more objective and provide a reference for those who would
# space-optimize.  This dir/script harness is such a set of e.g.s for Unix.
# You can probably just run: ./build.sh; xs=$(only ELF); strip $xs; ls -l $xs
# and util/exsz can perhaps help you explain sizes.  Good luck.

: ${nim:=nim}                   # Allow nim=whatever ./build.sh for other vsns.

t=$(mktemp -dp/tmp szProXXX)    # Scratch dir for parallel nimcache's

compile() {                     # Compile helper to name output after nim CL
    nm=$(echo "$@" | tr -d ' ')
    $nim c --nimcache:$t/"x@${nm}" \
                      -o:"x@${nm}" "$@" >/dev/null 2>&1
}

cc0="--threads:off --cc:gcc"                # Base options, then compile-modes
for cc in "$cc0 -d:danger --opt:size"               \
          "$cc0 -d:danger --opt:speed"              \
          "$cc0 -d:danger --opt:speed -d:useMalloc" \
          "$cc0 -d:danger --opt:speed -d:useMalloc --panics:on -d:lto" \
          "$cc0 -d:danger --opt:size  -d:useMalloc --panics:on -d:lto"
do
  ( for mm in "--mm:arc" "--mm:orc" ""      # various MMs
    do
      echo "nim: $nim  mm: $mm  cc: $cc"    # can take a while; show progress.
      compile $mm $cc empty &
      compile $mm $cc ostrut &
      compile $mm $cc popt3 &
      compile $mm $cc f &
      compile $mm $cc -d:cgCfgNone f &
      compile $mm $cc -d:cgCfgNone -d:cgNoColor f &
      wait
    done ) &
done
wait
rm -rf "$t"             # clean-up temp cache dir
