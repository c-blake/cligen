#!/bin/sh
exec < /dev/null
export COLUMNS=80
export CLIGEN=/dev/null
rm -rf $HOME/.cache/nim/*
for n in test/[A-Z]*.nim; do
  o=${n%.nim}.out
  c=$HOME/.cache/nim/cache-${n%.nim}
  ${nim:-nim} ${BE:-c} --nimcache:$c "$@" --run $n --help 2>&1 |
    grep -v '^CC:' > $o &
done
wait
./test/FullyAutoMulti help > test/FullyAutoMultiTopLvl.out 2>&1
./test/MultiMulti help > test/MultiMultiTopLvl.out 2>&1
head -n900 test/*.out | grep -v '^Hint: ' |
     sed -e 's@.*/cligen.nim(@cligen.nim(@' \
         -e 's@.*/test/@test/@' > test/out
rm -f test/*.out
diff test/ref test/out
