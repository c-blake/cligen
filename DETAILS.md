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
parameters or specifically positioned mandatory parameters are legal.
The name of the seq parameter does not matter, only that it's type slot is
non-empty and semantically `seq[SOMETHING]`.  When more than one such parameter
is in the proc signature, the first receives positional command args unless
you override that choice with the ``positional`` argument to ``dispatchGen``.

When there is no positional parameter catcher and no mandatory parameters, it
is a command syntax error to provide non-option parameters and reported as such.
This non-option syntax error also commonly occurs when requireSeparator=true.
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

Exit Code Behavior
==================
Commands return integer codes to operating systems to indicate exit status
(only the lowest order byte is significant on many OSes).  Conventionally, zero
status indicates a successful exit.  If the return type of the proc wrapped by
dispatch is int (or convertible to int) then that value will be propagated to
become the exit code.  Otherwise. `cligen` checks to see if `$` is in scope/echo
result works and echos it if so (unless `noAutoEcho` is passed).  Trying to echo
can be forced by passing ``echoResult=true``.  Command-line syntax errors cause
programs to exit with status 1 and print a help message.  Explicit requests for
help via --help or -h or --version, on the other hand, exit with status 0.

Usage String Adjustment
=======================
If you don't like the help message as-is, you can re-order it however you like
with some named-argument string interpolation:
```nim
  dispatch(foobar,          # swap place of doc string and options table
           usage="Use:\n$command $args\nOptions:\n$options\n$doc\n",
           prefix="   "))   # indent the whole message a few spaces.
```
Like usage string adjustment, there are many other knobs and tweaks available.
For even more details see the module documentations (
 [parseopt3](http://htmlpreview.github.io/?https://github.com/c-blake/cligen/blob/master/parseopt3.html)
 [argcvt](http://htmlpreview.github.io/?https://github.com/c-blake/cligen/blob/master/argcvt.html)
 [cligen](http://htmlpreview.github.io/?https://github.com/c-blake/cligen/blob/master/cligen.html) )
 and [RELEASE-NOTES](https://github.com/c-blake/cligen/tree/master/RELEASE-NOTES.md).
