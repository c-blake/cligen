#!/bin/sh
for n in test/[A-Z]*; do
  echo "Test: $n"
  nim c "$@" --run $n --help 2>&1 | grep -v '^CC:'
  echo "===================================="
done
