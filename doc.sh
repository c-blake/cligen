#!/bin/sh
for m in cligen cligen/parseopt3 cligen/argcvt; do
  if [ docs/$(basename $m).html -nt $m.nim ]; then
      echo $m html is up-to-date
      continue
  fi
  nim doc $m
  mv $(basename $m).html docs
done
