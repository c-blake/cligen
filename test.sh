#!/bin/sh
# If you cannot|refuse to run in an 80 column terminal|with no ctty at all then
#   x=$COLUMNS; stty columns 80; ./test.sh; stty columns $x
# will likely match reference output.  (NOTE: Final stty clobbers test.sh $?)
# But this script is really only for cligen developers.
exec < /dev/null
export COLUMNS=80
export CLIGEN=/dev/null
rm -rf $HOME/.cache/nim/*
v="--verbosity:1"
h="--hint[Processing]=off"
#XXX I do not know why the warning push in the code fails to suppress.
w="--warning[ObservableStores]:off"
if ${nim:-nim} c $w /dev/null 2>&1 | grep -q 'unknown warning:'; then
  w=""
fi
for n in test/[A-Z]*.nim; do
  o=${n%.nim}.out
  c=$HOME/.cache/nim/cache-${n%.nim}
  ${nim:-nim} ${BE:-c} --nimcache:$c $v $h $w "$@" --run $n --help 2>&1 |
    grep -v '\<CC: ' > $o &
done
wait
./test/FullyAutoMulti help > test/FullyAutoMultiTopLvl.out 2>&1
./test/MultiMulti help > test/MultiMultiTopLvl.out 2>&1
head -n900 test/*.out | grep -v '^Hint: ' |
     sed -e 's@.*/cligen.nim(@cligen.nim(@' \
         -e 's@.*/cligen/@cligen/@' \
         -e 's@.*/test/@test/@' > test/out
rm -f test/*.out
diff test/ref test/out
