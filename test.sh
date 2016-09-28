#!/bin/sh
exec < /dev/null
export COLUMNS=80
( for n in test/[A-Z]*.nim; do
  echo "Test: $n"
  nim c "$@" --run $n --help 2>&1 | grep -v '^CC:'
  echo "===================================="
done ) | grep -v 'Warning: \(expr\|stmt\) is deprecated' |
         grep -v '^Hint: ' > test/out 
diff test/ref test/out
