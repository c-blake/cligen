import std/options

proc demo*(optInt = none int): int =
  ## Show how to use `Option[T]`.  It unusual since, in order to not add time to
  ## compiles for all clients, we condition upon `cgDoOptions`.  `OptionT.nim`
  ## source shows how to activate this with `{.define(cgDoOptions).}`.
  ##
  ## Please note that the basic binding already provides for input optionality
  ## via simpler mechanisms of (at least) default values, user `mergeParams`
  ## protocols & `argParse` overloads.  See (at least!) `test/FancyRepeats.nim`,
  ## `test/FancyRepeats2.nim`, and `test/ParseOnly.nim`.
  ##
  ## At its core, this makes the value-if-none-given a CLauthor-implemented
  ## idea, outside the proc signature which induces a need to really document it
  ## in `help[optInt]`.  Also, complex wrapped types like `Option[seq[T]]` will
  ## probably not work fully at the CLuser level while they would with the
  ## `FancyRepeats.nim` way.  See https://github.com/c-blake/cligen/issues/212
  ## So, this is more intended for wrapping Nim APIs using `Option[T]` for other
  ## reasons (typically return values, not inputs).
  ##
  ## All that said, running this with -o1 vs. nothing produces distinct outputs.
  if optInt.isSome:
    echo optInt
  else:
    echo "`optInt` unspecified: using ", 1

when isMainModule:
  {.define(cgDoOptions).}
  import cligen; dispatch demo, help={"optInt": "1 if not specified"}
