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
This non-option syntax error also commonly occurs when requireSeparator=true
and traditional Nim parseopt2-like command syntax is in force.  In that case a
command user may forget the [:|=] required to separate an option and its value.

Extending `cligen` to support new parameter types (more on Rule 2)
------------------------------------------------------------------
`cligen` supports most basic Nim types (int, float, ..) out of the box, and the
system can be extended pretty easily to user-defined types.

You can extend the set of supported parameter conversion types by defining a
couple helper templates before invoking `dispatch`.  All you need do is define
a compatible `argParse` and `argHelp` for any new Nim parameter types you want.
Basically, `argParse` parses a string into a Nim value and `argHelp` provides
simple guidance on what that syntax is for command users.

For example, you might want to receive a `seq[string]` parameter inside a single
argument/option value.  So, you need some user friendly convention to convert
a single string to a sequence of them, such as a comma-separated-value list.
Teaching `cligen` what to do goes like this:
```nim
proc demo(stuff = @[ "abc", "def" ], opt1=true, foo=2): int =
  return len(stuff)

when isMainModule:
  import strutils, cligen, argcvt  # argcvt.keys deals with missing short opts

  template argParse(dst: seq[string], key: string, dfl: seq[string],
                    val: string, help: string) =
    dst = val.split(",")

  template argHelp(helpT: seq[array[0..3, string]], defVal: seq[string],
                   parNm: string, sh: string, parHelp: string, rq: int) =
    helpT.add([keys(parNm, sh), "CSV", argRq(rq, "\""&defVal.join(",")&"\""),
               parHelp])

  dispatch(demo, doc="NOTE: CSV=comma-separated value list")
```
Of course, you often want more input validation than this.  See `argcvt.nim` in
the `cligen` package for the currently supported types and more details.  Due
to ordinary Nim rules, if you dislike any of the default `argParse`/`argHelp`
implementations for a given type then you can override them by defining your
own in scope before invoking `dispatch`.  For example, `test/FancyRepeats.nim`
shows how to make `int` or `seq` behavior additive.

Exit Code Behavior
==================
Commands return integer codes to operating systems to indicate exit status
(only the lowest order byte is significant on many OSes).  Conventionally, zero
status indicates a successful exit.  If the return type of the proc wrapped by
dispatch is int (or convertible to int) then that value will be propagated to
become the exit code.  Otherwise the return of the wrapped proc is discarded
unless ``echoResult=true`` is passed in which case the result is printed as
long as there is a type to string/``$`` converter in scope.  Command-line
syntax errors cause programs to exit with status 1 and print a help message.

Usage String Adjustment
=======================
If you don't like the help message as-is, you can re-order it however you like
with some named-argument string interpolation:
```nim
  dispatch(foobar,          # swap place of doc string and options table
           usage="Use:\n$command $args\nOptions:\n$options\n$doc\n",
           prefix="   "))   # indent the whole message a few spaces.
```
