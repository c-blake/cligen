#!/bin/sh
exec < /dev/null
export COLUMNS=80
for n in test/[A-Z]*.nim; do
  o=${n%.nim}.out
  c=$HOME/.cache/nim/cache-${n%.nim}
  nim c --nimcache:$c "$@" --run $n --help 2>&1 | grep -v '^CC:' > $o &
done
wait
./test/FullyAutoMulti help > test/FullyAutoMultiTopLvl.out 2>&1
head -n900 test/*.out | grep -v '^Hint: ' |
     sed -e 's@.*/cligen.nim(@cligen.nim(@' \
         -e 's@.*/cligen/test@cligen/test@' > test/out
rm -f test/*.out
diff --ignore-all-space test/ref test/out
