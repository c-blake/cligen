#!/bin/sh
exec < /dev/null
export COLUMNS="80" CLIGEN_WIDTH="80" CLIGEN=/dev/null
rm -rf $HOME/.cache/nim/*
v="--verbosity:2"
h="--hint[Path]:off --hint[Conf]:off --hint[Processing]:off --hint[CC]:off"
h="$h --hint[Exec]:off --hint[Source]:off --hint[Link]:off --hint[SuccessX]:off"
h="$h --hint[GCStats]:off"
: ${w="--warning[Deprecated]:off --warning[ProveField]:off"}
for n in test/[A-Z]*.nim; do
  o=${n%.nim}.out
  c=$HOME/.cache/nim/cache-${n%.nim}
  ${nim:-nim} ${BE:-c} --nimcache:$c $v $h $w "$@" --run $n --help > $o 2>&1 &
done
wait
for n in $(grep -lw dispatchMulti test/*nim); do
    p=${n%.nim}; p=${p#test/}
    ./test/$p help > test/${p}TopLvl.out 2>&1
done
head -n900 test/*.out | grep -v '^Hint: ' |
     sed -e 's@.*/cligen.nim(@cligen.nim(@' \
         -e 's@.*/cligen/@cligen/@' \
         -e 's@.*/test/@test/@' | tr -d \\037 > test/out
rm -f test/*.out
diff test/ref test/out
