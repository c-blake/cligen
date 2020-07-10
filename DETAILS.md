Some Limitations/Rules, more rare dispatch controls
===================================================

Basic Requirements For A Proc To Have A Well-Inferred Command
=============================================================
There are only a few very easy rules to learn:

 1. Zero or 1 params has type seq[T] to catch optional positional args.
   
 2. All param types used must have argParse, argHelp support (see Extending..)
    This includes the type T in seq[T] for non-option/positionals.

 3. Only basic procs supported -- no 'auto' types, 'var' types, generics, etc.
   
 4. No param of a wrapped proc can be named "help".  (Name collisions!)

Optional positional command arguments (more on Rule 1)
------------------------------------------------------
When there is no `seq[T]` parameter, `cligen` infers that only option command
parameters or specifically positioned required parameters are legal.
The name of the `seq` parameter does not matter, only that it's type slot is
non-empty and semantically `seq[SOMETHING]`.  When more than one such parameter
is in the proc signature, the first receives positional command args unless
you override that choice with the ``positional`` argument to ``dispatchGen``.

When there is no positional parameter catcher and no required parameters, it is
a command syntax error to provide non-option parameters and reported as such.
This non-option syntax error also commonly occurs when `clCfg.reqSep==true`.
In that case a command user may forget the [:|=] required to separate an option
and its value.

Extending `cligen` to support new parameter types (more on Rule 2)
------------------------------------------------------------------
`cligen` supports most basic Nim types out of the box (strings, numbers, enums,
sequences and sets of such, etc.).  To extend the set of supported parameter
conversion types, all you need do is define compatible `argParse` and `argHelp`
procs for the new Nim parameter types.  Basically, `argParse` parses a string
into a Nim value and `argHelp` provides simple guidance on what that syntax is
for command users and formats a default value - the input & output.

For example, you might want to receive a named color parameter from the Nim
colors module.  Teaching `cligen` what to do goes like this:
```nim
import colors, cligen, cligen/argcvt

proc demo(color = colBlack, opt1=true, paths: seq[string]): int =
  echo "color=", color

proc argParse(dst: var Color, defaultValue: Color, a: var ArgcvtParams): bool =
  try:
      dst = parseColor(a.val)
  except:
      stderr.write(a.val, " is not a known color name\n", a.help)
      return false
  return true

proc argHelp(defaultValue: Color, a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys, "Color", a.argDf($defaultValue) ]

dispatch(demo, doc="NOTE: colors.nim has color names")
```
See `argcvt.nim` in the `cligen` package for currently supported types and
more details.  Due to ordinary Nim rules, if you dislike any of the default
`argParse`/`argHelp` implementations for a given type then you can override
them by defining your own in scope before invoking `dispatch`.  For example,
`test/FancyRepeats.nim` shows how to make repeated `int` or `seq` issuance
additive without "+=" syntax.

----

There are many adjustments available.  For more details see the module
documentations ([parseopt3](http://c-blake.github.io/cligen/cligen/parseopt3.html)
                [argcvt](http://c-blake.github.io/cligen/cligen/argcvt.html)
                [cligen](http://c-blake.github.io/cligen/cligen.html) ) and
[RELEASE-NOTES](https://github.com/c-blake/cligen/tree/master/RELEASE-NOTES.md).
