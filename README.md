cligen: A Native API-Inferred Command-Line Interface Generator For Nim
======================================================================
This approach to CLIs comes from Andrey Mikhaylenko's nice Python module 'argh'.
Much as with Python, an intuitive subset of ordinary Nim calls maps cleanly onto
command calls, syntactically and semantically.  For Nim, that subset is any
non-generic proc with non-var parameters typed either by default value inference
or by explicit types (i.e., not like `foo(b: auto)`).  The proc must also have
some seq[T] *if* it wants to receive a variable list of optional positional
parameters after optional and specific mandatory parameters.  For such procs,
`cligen` can automatically generate a nice-ish command-line interface complete
with long and short options and a nice-ish help message.

Enough Generalities...Show me examples!
---------------------------------------
In Nim terms, adding a CLI can be as easy as:
```nim
proc foobar(foo=1, bar=2.0, baz="hi", verb=false, paths: seq[string]): int =
  ##Some existing API call
  result = 1          # Of course, real code would have real logic here

when isMainModule:
  import cligen
  dispatch(foobar)    # Yep..It can really be this simple!
```
Compile it to foobar (assuming nim c foobar.nim is appropriate, say) and then
run ./foobar --help to get a minimal (but not so useless) help message:
```
Usage:
  foobar [optional-params] [paths]
Some existing API call
Options (opt&arg sep by :,=,spc):
--help, -?                  print this help message
--foo=, -f=  int     1      set foo
--bar=, -b=  float   2.0    set bar
--baz=       string  "hi"   set baz
--verb, -v   toggle  false  set verb
```
Other invocations (foobar --foo=2 --bar=2.7 ...) all work as you would expect.

When you feel like producing a better help string, tack on some parameter-keyed
metadata with Nim's association-list literals and maybe throw in a more overall
description of operation doc string for before the options table:
```nim
  dispatch(foobar, doc = "Deletes no positional-params!",
           help = { "foo" : "the beginning", "bar" : "the rate" })
```
If you want to manually control the short option for a parameter, you can
just override it with the 5th|short= macro parameter:
```nim
  dispatch(foobar, short = { "bar" : 'r' }))
```
With that, "bar" will get 'r' while "baz" will get 'b'.

If you don't like the help message as-is, you can re-order it however you like
with some named-argument string interpolation:
```nim
  dispatch(foobar,          # swap place of doc string and options table
           usage="Use:\n$command $args\nOptions:\n$options\n$doc\n",
           prefix="   "))   # indent the whole message a few spaces.
```

The same basic string-to-native type converters used for option values will be
applied to convert optional positional arguments to seq[T] values or mandatory
positional arguments to values of their types:
```nim
proc foobar(myMandatory: int, mynums: seq[int], foo=1, verb=false): int =
  ##Some API call
  result = 1          # Of course, real code would have real logic here
when isMainModule:
  import cligen; dispatch(foobar)
```
That's basically it.  Many users who have read this far can start using `cligen`
without further delay.  The rest of this document may be useful later, though.

By default, dispatchGen sets requireSeparator=false which results in more
traditional POSIX command-line parsers than parseopt/parsopt2 in Nim's standard
library.  Specifically, ``-abcdBar`` or ``-abcd Bar`` or ``--delta Bar`` or
``--delta=Bar`` are all acceptable syntax for command options.

Basic Requirements For A Proc To Have A Well-Inferred Command
=============================================================
There are only a few very easy rules to learn:

 0. No parameter of a wrapped proc can can be named "help" (name collision!)
   
 1. Zero or one params has explicit type seq[T] to catch positional arguments.
   
 2. All param types used must have argParse, argHelp support (see Extending..)
    This includes the type T in seq[T] for non-option/positionals.

 3. Only basic procs supported -- no 'auto' types, 'var' types, generics, etc.

That's about it.  `cligen` supports most basic Nim types (int, float, ..) out
of the box, and the system can be extended pretty easily to user-defined types.
Elaboration on these rules may be helpful when/if you run into harder cases.

Forbidding optional positional command arguments (more on Rule 1)
-----------------------------------------------------------------
When there is no explicit `seq[T]` parameter, `cligen` infers that only option
command parameters or specifically positioned mandatory parameters are legal.
The name of the seq parameter does not matter, only that it's type slot is
non-empty and syntactically `seq[SOMETHING]` as opposed to some type alias/etc.
that happens to be a `seq`.  When there is no positional parameter catcher and
no mandatory parameters, providing non-option parameters is a command syntax
error and reported as such.  `cligen` may someday grow the ability to specify
which proc parameter catches optional command positional parameters (rather
than inferring that parameter from being the only/first explicit `seq[T]`).

This non-option syntax error also commonly occurs when requireSeparator=true is
passed and traditional Nim parseopt2-like command syntax is in force.  In that
case a command user may forget the [:|=] required to separate an option and its
value.  The default posix-style backend does not require separators.

Extending `cligen` to support new parameter types (more on Rule 2)
------------------------------------------------------------------
You can extend the set of supported parameter conversion types by defining a
couple helper templates before invoking `dispatch`.  All you need do is define a
compatible `argParse` and `argHelp` for any new Nim parameter types you want.
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

  template argParse(dst: seq[string], key: string, val: string, help: string) =
    dst = val.split(",")

  template argHelp(helpT: seq[array[0..3, string]], defVal: seq[string],
                   parNm: string, sh: string, parHelp: string) =
    helpT.add([keys(parNm, sh), "CSV", "\"" & defVal.join(",") & "\"", parHelp])

  dispatch(demo, doc="NOTE: CSV=comma-separated value list")
```
Of course, you often want more input validation than this.  See `argcvt.nim` in
the `cligen` package for the currently supported types and more details.

Note also that, since `stuff` is a `seq` and there can be only one `seq[T]` for
positionals, type inference for `stuff=@[...]` in the above example is required.
Using `(stuff: seq[string] = @[...],...)` would yield either an error or the
unintended syntax (`command --foo=3 "a,b,c" "d,e,f"` rather than `--stuff="a,b,c"`).

Exit Code Behavior
==================
Commands return integer codes to operating systems to indicate exit status
(only the lowest order byte is significant on many OSes).  Conventionally, zero
status indicates a successful exit.  If the return type of the proc wrapped by
dispatch is int or convertible to int then that value will be propagated to
become the exit code.  Otherwise the return of the wrapped proc is discarded.
Command-line syntax errors cause programs to exit with status 1 and print a help
message.

More Motivation
===============
There are so many CLI parser frameworks out there...Why do we need yet another?
This approach to command-line interfaces has both great Don't Repeat Yourself
("DRY", or relatedly "a few points of edit") properties.  It also has nice
"loose coupling" properties.  `cligen` need not even be *present on the system*
unless you are compiling a CLI executable.  Similarly, wrapped routines need
not be in the same module, modifiable, or know anything about `cligen`.  This
approach is great when you want to maintain both an API and a CLI in parallel.
More generally, `cligen` encourages preserving API/"Nim import"-access to any
provided functionality.  When so preserved, this simplifies complex uses being
driven by other Nim programs rather than shell scripts (once usage complexity
makes scripting language limitations annoying).  Finally, and perhaps most
importantly, the learning curve/cognitive load and even the extra program text
for a CLI is all about as painless as possible - mostly learning what kind of
proc is "command-like" enough, various minor controls/arguments to `dispatch` to
enhance the help message, and the "binding/translation" between proc and command
parameters.  The last is helped a lot by the auto-generated help message.

Future directions/TODO
======================
 - Automate git/nimble-like multi-dispatch (see ManualMulti, SemiAutoMulti.nim)

 - Might be nice to be able to pass through (from dispatch) colGap, min4th, and
   maybe a new param to double-space optionally (extra \n between optTab rows).
   [dispatch getting to be a pretty fat interface, but formatting usually is.]

 - Better error reporting. E.g., help={"foo" : "stuff"} silently ignores "foo"
   if there is no such parameter.  Etc.

 - Could use argv "--" separator to allow multiple positional sequences.  Could
   also allow user override in dispatchGen arg to specify which proc param gets
   bound to the optional positionals.
