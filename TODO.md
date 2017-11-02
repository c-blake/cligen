  Might be nice to have some encapsulation/abstration of macro parameters since
  some might be re-used a lot, especially in a ``dispatchMulti`` setting.  Maybe
  parserOpts and helpOpts.  Would probably be even nicer if Nim had some general
  mechanism to package up parameter subsets like Python's ``**kwargs``.

  Might be nice to have dispatchMulti be able to take long<->in-scope variable
  bindings to provide global options <-> variables.  This approach might also
  be a basis for a totally distinct dispatchGen that takes such bindings rather
  than inferring them from the proc signature.

  Better error reporting. E.g., ``help={"foo" : "stuff"}`` silently ignores the
  ``"foo"`` if there is no such parameter.  Etc.

  Could use argv "--" separator to allow multiple positional sequences.

  Should at least ask if there is any interest in parseopt3.nim in stdlib.

  Would be nice to give dispatch a 'suppress' list to block certain parameters
  from CLI modification.

  Should be able to specify for some seq params that they are populated by
  repeated option key instances (like the include path of cc -I).

  This is really advanced and goes beyond most CLI apis, but it might also be
  nice to have input data from stdin auto-converted to an iterator/seq and an
  output convention for emitting to stdout [ e.g., a designated output seq
  parameter with seq.add -> (seq.add; echo) and maybe some designated input
  parameter and a flag as to whether to merge argv/stdin as sources of inputs,
  etc. ].  Can also generalize text IO to binary/RPC/other serialized formats.
  If output/input format are "compatible"/inverses this might let a module of
  similar procs be compilable into a multi-command that was very pipelinable.
