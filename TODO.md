  Might be nice to have some encapsulation/abstration of macro parameters since
  some might be re-used a lot, especially in a ``dispatchMulti`` setting.  Maybe
  parserOpts and helpOpts.  Would probably be even nicer if Nim had some general
  mechanism to package up parameter subsets like Python's ``**kwargs``.

  Might be nice to have dispatchMulti be able to take long<->in-scope variable
  bindings to provide global options <-> variables.  This approach might also be
  a basis for a totally distinct dispatchGen that takes such bindings rather
  than inferring them from the proc signature.

  Allow an option to drop the type column from the help message.

  Better error reporting. E.g., ``help={"foo" : "stuff"}`` silently ignores the
  ``"foo"`` if there is no such parameter.  Etc.

  The help table itself could be more "text template"-ish.

  Could use argv "--" separator to allow multiple positional sequences.  Could
  also allow user override in dispatchGen arg to specify which proc param gets
  bound to the optional positionals.

  Should try to get ``termwidth`` into Nim stdlib.  Seems very generally useful.

  Should at least ask if there is any interest in parseopt3.nim in stdlib.
