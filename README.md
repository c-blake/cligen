cligen: A Native API-Inferred Command-Line Interface Generator For Nim
======================================================================
This approach to CLIs comes from Andrey Mikhaylenko's nice Python argh module.
To my knowledge, argh was the first software with the great insight that a CLI
generator could be so automatic.  It does require a programming language with
both rich enough call syntax and powerful enough introspection -- like Nim.
Much as with Python, an intuitive subset of ordinary Nim calls maps pretty
cleanly onto command calls, both syntactically and semantically.

That subset is basically any proc with all parameters having default values and
maybe a final param to catch some positional argument list and a return type of
int or no return type at all.  proc definitions in that convention directly
imply a command interface..All we need to do is extract metadata, generate a
parser, and call the proc.  Less "command conventional" styles of proc still
need some manually written entry point that does follow the simple convention.

This approach has both great DoNot Repeat Yourself ("DRY", or relatedly "a few
points of edit") properties.  It also has nice "loose coupling" properties.
`cligen` need not even be *present on the system* unless you are compiling a
CLI executable.  Conversely, the wrapped routine does not need to be in the
same module or even a writable file or know anything about `cligen`.  Learning
curve/cognitive load is all just about as painless as possible.

Enough Background..Get To The Good Stuff!
-----------------------------------------
In Nim terms, adding a CLI can be as easy as:
```nim
proc foobar(foo=1, bar=2.0, baz="hi", verb=false, paths: seq[string]): int =
  #Some existing API call with all params defaulted but for a final seq[string]
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
Options:
  --help, -?                    print this help message
  --foo=, -f=   int     1       set foo
  --bar=, -b=   float   2.0     set bar
  --baz=        string  "hi"    set baz
  --verb, -v    toggle  false   set verb
```
Other invocations (foobar --foo=2 --bar=2.7 ...) all work as you would expect.

When you feel like producing a better help string, tack on some parameter-keyed
metadata with Nim's association-list literals and maybe throw in an more overall
description of operation doc string for before the options table:
```nim
  dispatch(foobar, doc = "Deletes no positional-params!",
           help = { "foo" : "the beginning", "bar" : "the rate" })
```
If you want to manually disambiguate the first letter rule or otherwise control
short options then override it with the 5th|short= macro parameter:
```nim
  dispatch(foobar, short={ "bar" : 'r' }))
```
With that, "bar" will get 'r' while "baz" will get 'b'.

If you don't like the help message as-is, you can re-order it however you like
with some named-argument string interpolation:
```nim
  dispatch(foobar,          # swap place of doc string and options table
           usage="Use:\n$command $optPos\nOptions:\n$options\n$doc\n",
           prefix="   "))   # indent the whole message a few spaces.
```

That's basically it.  If there is no all-defaulted maybe-seq[string] entry point
then just write one in ordinary Nim style.  Many users who have read this far
can start using cligen without further delay.  The rest of this document may be
useful later, though.

Basic Requirements For A Proc To Have A Well-Inferred Command
=============================================================
There are only a few very easy rules to learn, two of which are obvious enough
to not even warrant Natural numbers ;-), two of which you may have intuited
already by example/off-hand mention, and the last of which you could guess:

 0a. Optional params get default values (Um, how else can the be optional?)
   
 0b. No parameter of a wrapped proc can can be named "help" (collision!)
   
 1. If the last proc parameter is seq[string], it catches non-option arguments

 2. Wrapped procs must have no return or a return type convertible to int.
   
 3. All param types used must have argParse, argHelp support (see Extending..)

That's about it.  `cligen` supports the most likely Nim types (int, float, ..)
out of the box, and the system can be extended pretty easily.  Elaboration on
these rules may be helpful when/if you run into harder cases.

Forbidding positional command arguments (more on Rule 1)
-------------------------------------------------------
If there is no final seq[string], cligen infers that only optional command
parameters are legal.  The name of the seq parameter does not matter, only its
final position and its type.  When there is no positional argument catcher,
providing non-option arguments is a command syntax error and reported as such.

This syntax error also commonly occurs when a command user forgets the [:|=] to
separate an option and its value.  Nim's parsopt2, the current cligen backend,
requires such separators.  Many other option parsers do not require separators,
especially for short options.  So, it's easy to forget. [ Those other parsers
have ways to specify that an option is non-bool and should take an argument. ]

It is possible to relax this constraint to any proc that has *exactly one*
supported, non-defaulted seq[T] anywhere in the argument list.  The str->val
machinery for optional arguments can simply be re-applied to positionals.

Exit Code Behavior (more on Rule 2)
-----------------------------------
Commands/programs/processes return integer codes to indicate exit status (only
the lowest order byte is significant on many OSes).  All command-line syntax
errors cause programs to exit with status 1.  If there is no return type then
zero is returned to indicate a successful exit (unless an exception is thrown).
If the return type of the wrapped proc is not int, Nim will try to apply any
in-scope converter.  If there is no converter toInt(rtype) the macro will fail
with an error of the form "got (rtype) but expected 'int'" with the line number
of macro invocation.

While there may be some "when compiles()" magic that could fall back to discard
the return value and return zero for non-convertible-to-int's, it may be wiser
to make dispatch() users think a little about mapping non-integer return values
to exit codes.  Defining a little wrapper proc that returns an int (or has no
return) may be easier or clearer than defining a converter, but that does mean
when you add a parameter to your entry point proc you have to add it in two
places which isn't very DRY.  Meh.  If popular demand ensues, discarding
non-convertible-to-int's isn't so hard or so bad.

Extending cligen to support new optional parameter types (more on Rule 3)
--------------------------------------------------------------------------
You can extend the set of supported types by defining a couple helper templates
before invoking dispatch().  All you need to do is define a compatible argParse
and argHelp for any new Nim parameter types you want.  Basically, argParse
parses a string into a Nim value and argHelp provides simple guidance on what
that syntax is for command users.

For example, you might want to receive a seq[string] parameter.  The input will
be a command option value string.  So, you need some user friendly convention,
such as comma-separated-value list. Teaching cligen what to do goes like this:
```nim
proc demo(stuff = @[ "abc", "def" ]): int =
  return len(stuff)

when isMainModule:
  import strutils, argcvt   # argcvt.keys deals with missing short opts

  template argParse(dst: seq[string], key: string, val: string, help: string) =
    dst = val.split(",")

  template argHelp(helpT: seq[array[0..3, string]], defVal: seq[string],
                   parNm: string, sh: string, parHelp: string) =
    helpT.add([keys(parNm, sh), "CSV", "\"" & defVal.join(",") & "\"", parHelp])

  import cligen; dispatch(demo, doc="NOTE: CSV=comma-separated value list")
```
Of course, you often want more input validation than this.  See argcvt.nim in
the cligen package for the currently supported types and more details.

Related Work
============
`docopt` has similar DRY features, provides superior control over help messages
and much richer command line syntaxes -- necessary/mutually exclusive options
and such.  The downside to using it is learning the whole "codified" POSIX
help string syntax and having non-natural parameter access/docopt API calls
all over user code.  Basically, docopt is a forethought- rather than an
afterthought-CLI framework.  Consider that it makes little sense to invoke the
same docopt program entry point from other Nim code.  There are surely pros
and cons.  Implied/inferred CLIs do require a stronger programming language.

Additionally, cligen encourages people to preserve Nim-import ways to access
provided functionality.  Simple uses get simple commands.  Complex usages and
composition with other APIs can flow to other Nim programs rather than messy
shell scripts (or such scripts can be easily converted to Nim when command
script/shell language limitations become bothersome).

Future directions/TODO
======================
I felt cligen was useful enough right now to release.  That said..the TODO is
long-ish and includes what many might deem "basic features" :-)

 - Might be nice to be able to pass through (from dispatch) colGap, min4th, and
   maybe a new param to "double space" optionall (extra \n between optTab rows).
   [dispatch getting to be a pretty fat interface, but formatting usually is.]

 - Better error reporting. E.g., help={"foo" : "stuff"} silently ignores "foo"
   if there is no such parameter.  Etc.

 - Automate git/nimble-like multi-dispatch. Not so bad..See test/ManualMulti.nim
   Because subcmds are a hard boundary in argv, this needs to do its own opt/arg
   parsing and hard-stop at the first non-option or at least valid subcmd names.

 - Would be nice to provide control over option parsing backend instead of just
   always using parseopt2. Can roll own more traditionally Unix-y backend.  Can
   infer that only bool options can not expect arguments, and can be combined
   like "ls -lt" while non-bool options require vals and need no :|= separator.

 - We can relax catching positionals in seq[string] to seq[T] for any T that
   argParse/argHelp can deal with. Can pass argParse key=""|nil to distinguish.
   But better user error msgs might come from new argParse with int "key" param.

 - It might be nice to provide control over what dialect is used to translate
   "multiWord" parameter idents command syntax ("--multi-word", --multi_word,..)
   or maybe most Nim-like to just accept all such dialects? { Maybe all that's
   needed is a strutils.normalize() that takes out "-" as well as "_". }

 - In Nim, ##-doc comments are the norm rather than doc strings as in Python.
   Present issues with Nim getImpl and/or my ignorance prevent easy/afterthought
   collection of such text.  Pragma macros can get the text, but my guess is
   the driving idea behind getImpl of user-driven inlining led to unnecessary
   (and for cligen undesirable) stripping of comment nodes.  In the not too
   distant future maybe such extraction can build usage/help out of existing
   API doc comments. E.g., a param <-> semantic help could be lifted from API
   code looking like:
     proc demo(foo=1,         ## critical flag..
               bar=2): int =  ## nobody cares)
   and maybe the first big ## mentioning `foo`, `bar`, etc. that gets into
   the help.  This could really lessen the need for doc= (and/or help=).
