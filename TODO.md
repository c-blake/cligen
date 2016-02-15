  Might be nice to be able to pass through (from dispatch) colGap, min4th, and
  maybe a new param to double-space optionally (extra \n between optTab rows).
  [dispatch getting to be a pretty fat interface, but formatting usually is.]

  Better error reporting. E.g., help={"foo" : "stuff"} silently ignores "foo"
  if there is no such parameter.  Etc.

  Could use argv "--" separator to allow multiple positional sequences.  Could
  also allow user override in dispatchGen arg to specify which proc param gets
  bound to the optional positionals.

  Should try to get `termwidth` into Nim stdlib.  Seems very generally useful.

  Should at least ask if there is any interest in parseopt3.nim in stdlib.
