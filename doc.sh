#!/bin/sh
for m in cligen cligen/parseopt3 cligen/argcvt; do
  nim doc $m
  mv $(basename $m).html docs
done
