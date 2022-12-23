#!/bin/sh
exec < /dev/null
export COLUMNS="80" CLIGEN_WIDTH="80" CLIGEN=/dev/null
rm -rf $HOME/.cache/nim/*
v="--verbosity:1"
h="--hint[Processing]=off --hint[SuccessX]=off"
#XXX I do not know why the warning push in the code fails to suppress.
: ${w="--warning[ObservableStores]:off --warning[Deprecated]:off"}
if ${nim:-nim} c $w /dev/null 2>&1 | grep -aq 'unknown warning:'; then
  w=""
fi
for n in test/[A-Z]*.nim; do
  o=${n%.nim}.out
  c=$HOME/.cache/nim/cache-${n%.nim}
  ${nim:-nim} ${BE:-c} --nimcache:$c $v $h $w "$@" --run $n --help 2>&1 |
    grep -v '\<CC: ' > $o &
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
