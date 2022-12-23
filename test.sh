#!/bin/sh
exec < /dev/null
export COLUMNS="80" CLIGEN_WIDTH="80" CLIGEN=/dev/null
rm -rf $HOME/.cache/nim/*
v="--verbosity:1"
h="--hint[Processing]=off --hint[CC]=off --hint[Exec]=off --hint[SuccessX]=off"
: ${w="--warning[ObservableStores]:off --warning[Deprecated]:off"}
if ${nim:-nim} c $w /dev/null 2>&1 | grep -aq 'unknown warning:'; then
  w=""
fi
for n in test/[A-Z]*.nim; do
  o=${n%.nim}.out
  c=$HOME/.cache/nim/cache-${n%.nim}
  #`cat` here is needed to integrate the [User] warning in the output stream.
  ${nim:-nim} ${BE:-c} --nimcache:$c $v $h $w "$@" --run $n --help 2>&1|cat>$o&
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
