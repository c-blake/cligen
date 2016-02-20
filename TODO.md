  Better error reporting. E.g., help={"foo" : "stuff"} silently ignores "foo"
  if there is no such parameter.  Etc.

  The help table itself could be more "text template"-ish.

  Could use argv "--" separator to allow multiple positional sequences.  Could
  also allow user override in dispatchGen arg to specify which proc param gets
  bound to the optional positionals.

  Should try to get `termwidth` into Nim stdlib.  Seems very generally useful.

  Should at least ask if there is any interest in parseopt3.nim in stdlib.
