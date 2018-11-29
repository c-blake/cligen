  Might be nice to have some encapsulation/abstraction of macro parameters since
  some might be re-used a lot, especially in a ``dispatchMulti`` setting.  Maybe
  `parseCtl`, `helpCtl`, `dispatchCtl`.  Using a Nim template/macro wrapper is
  easy for `dispatch`, but that would not help with `dispatchMulti`.

  This is really advanced and goes beyond most CLI APIs, but it may also be nice
  to have input data from stdin (optionally mergeable with argv) auto-parsed to
  designated input `seq[T]` and also allow formatting controls for result echo.
  Then procs which take `seq[T]` & return `seq[U]` could be easily wrapped into
  cmds that read from auto-parsed data on stdin, compute, format data to stdout.
  In real commands, such activity is often buffered not one-shot, though.  While
  we might be able to use an `iterator(): T` on the input side, there seems no
  way to buffer the output incrementally which could mean a lot of memory use to
  store `seq[U]`.  Automatic read-side buffered parsing could still be nice,
  though existing procs in the wild with `iterator(): T` input must be much more
  rare than `(openArray|seq)[T]`.  Could also generalize text IO to binary/RPC
  marshaled fmts.  If output/input fmt are compatible/inverses this might allow
  elegant construction of a multi-command of pipelinable subcommands.
