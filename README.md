cligen: A Native API-Inferred Command-Line Interface Generator For Nim
======================================================================
This approach to CLIs was inspired by [Andrey Mikhaylenko's nice Python module
'argh'](https://pythonhosted.org/argh/).  The basic idea is that proc signatures
encode/declare almost everything needed to generate a CLI - names, types, and
default values.  A little reflection/introspection then suffices to generate a
parser-dispatcher that translates a `seq[string]` command input into proc calls.
In Nim, adding a CLI can be as easy as adding a single line of code:
```nim
proc foobar(foo=1, bar=2.0, baz="hi", verb=false, paths: seq[string]): int =
  ##Some existing API call
  result = 1          # Of course, real code would have real logic here
import cligen; dispatch(foobar) #Whoa..Just 1 line??
```
Compile it to foobar (e.g., ``nim c foobar.nim``) and then run ``./foobar
--help`` to get a minimal (but not so useless!) help message:
```
Usage:
  foobar [optional-params] [paths]
Some existing API call

Options (opt&arg sep by :,=,spc):
  -h, --help                  print this help message
  -f=, --foo=  int     1      set foo
  -b=, --bar=  float   2.0    set bar
  --baz=       string  "hi"   set baz
  -v, --verb   toggle  false  set verb
```
Other invocations (``foobar --foo=2 --bar=2.7 ...``) all work as expected.

When you want to produce a better help string, tack on some parameter-keyed
metadata with Nim's association-list literals:
```nim
dispatch(foobar, help = { "foo" : "the beginning", "bar" : "the rate" })
```
That's it.  No specification language or complex arg parsing APIs.  If you
aren't immediately sold, here is some more
[motivation](https://github.com/c-blake/cligen/tree/master/MOTIVATION.md).

---

The same basic string-to-native type converters used for option values will be
applied to convert optional positional arguments to `seq[T]` values or mandatory
positional arguments to values of their types:
```nim
proc foobar(myMandatory: int, mynums: seq[int], foo=1, verb=false): int =
  ##Some API call
  result = 1        # Of course, real code would have real logic here
when isMainModule:  # Preserve ability to `import api` & call from Nim
  import cligen; dispatch(foobar)
```

---

`dispatchMulti` lets you expose two or more procs with subcommands a la `git` or
`nimble`, just use in, say, a `cmd.nim` file.  Each `[]` list in `dispatchMulti`
is the argument list for each sub-`dispatch`.  Tune command syntax and help
strings in the same way as ``dispatch`` as in:
```nim
proc foo(myMandatory: int, mynums: seq[int], foo=1, verb=false) =
  ##Some API call
proc bar(yippee: int, myfloats: seq[float], verb=false) =
  ##Some other API call
when isMainModule:
  import cligen; dispatchMulti([foo, help={"myMandatory": "Need it!"}], [bar])
```
With that, a CLI user can run ``./cmd foo -m1`` or ``./cmd bar -y10 1.0 2.0``.
``./cmd --help`` will emit a brief help message and ``./cmd help`` emits a more
comprehensive message, while ``./cmd subcommand --help`` emits just the message
for ``subcommand``.

---

Many CLI authors who have understood things this far can use `cligen` already.
Enter illegal commands or `--help` to get help messages to exhibit the mappings.

More Controls For More Subtle Cases/More Picky CLI authors
==========================================================
You can manually control the short option for any parameter via the `short` macro
parameter:
```nim
dispatch(foobar, short = { "bar" : 'r' }))
```
With that, ``"bar"`` gets ``'r'`` while ``"baz"`` gets ``'b'`` as short options.
To suppress a long option getting *any* short option, specify ``'\0'`` as the
value for its short key.  To suppress _all_ short options, give ``short`` a key
of ``""``.

---

By default, ``dispatch`` has ``requireSeparator=false`` making ``-abcdBar``,
``-abcd Bar``, ``--delta Bar`` or ``--delta=Bar`` all acceptable syntax for
command options.  Additionally, long option keys can be spelled flexibly, e.g.
``--dry-run`` or ``--dryRun``, much like Nim's style-insensitive identifiers.

---

If it makes more sense to echo a convertible-to-int8-exit-code result of a proc
then just pass ``echoResult=true``:
```nim
import editdistance, cligen   # gen a CLI for Nim stdlib's editDistance
dispatch(editDistanceASCII, echoResult=true)
```
If result _cannot_ be converted to `int`, `cligen` tries to `echo` the result
if possible (unless you tell it not to by passing `noAutoEcho=true`).

If _neither_ `echo`, nor conversion to `int` exit codes does the trick OR if you
want to control program exit OR to call dispatchers more than once OR on more
than one set of `seq[string]` args then you may need to call `dispatchGen()`
and later call `dispatchFoo()` yourself.  This is all `dispatch` itself does.

The return _types and values_ of generated dispatchers match those of the
wrapped proc.  The first parameter is a `seq[string]`, just like a command line.
{ Other parameters are knobs to aid in nested call settings that are defaulted
and probably don't matter to you. } The dispatcher raises 3 exception types:
`HelpOnly`, `VersionOnly`, `ParseError`.  These are hopefully self-explanatory.

---

If you want `cligen` to merge parameters from other sources like a `$CMD`
environment variable then you can redefine `mergeParams()` after `import cligen`
but before `dispatch`/`dispatchMulti`:
```nim
import cligen, os, strutils
proc mergeParams(cmdNames: seq[string], cmdLine=commandLineParams()): seq[string]=
  let e = os.getEnv(toUpperAscii(join(cmdNames, "_")))   #Get $MULTI_(FOO|_BAR)
  if e.len > 0: parseCmdLine(e) & cmdLine else: cmdLine  #See os.parseCmdLine
dispatchMulti([foo, short={"verb": 'v'}], [bar])
```
You can, of course, also have `mergeParams` use the `parsecfg` module to convert
`$HOME/.cmdrc`, `${XDG_CONFIG:-$HOME/.config}/cmd`, .. into a `seq[string]` that
is relevant to `cmdNames`.

---

Default help tables work with automated "help to X" tools such as ``complete -F
_longopt`` in bash, ``compdef _gnu_generic`` in zsh, or the GNU ``help2man``.

Even More Controls and Details
==============================
After many feature requests `cligen` grew many knobs & levers.  First there are
more [DETAILS](https://github.com/c-blake/cligen/tree/master/DETAILS.md) on the
restrictions on wrappable procs and extending the parser to new argument types.

Then there is the documentation for the three main modules:
  [parseopt3](http://htmlpreview.github.io/?https://github.com/c-blake/cligen/blob/master/parseopt3.html)
  [argcvt](http://htmlpreview.github.io/?https://github.com/c-blake/cligen/blob/master/argcvt.html)
  [cligen](http://htmlpreview.github.io/?https://github.com/c-blake/cligen/blob/master/cligen.html)

A good starting point for various advanced usages is the many examples in my
automated test suite:
  [test/](https://github.com/c-blake/cligen/tree/master/test/).

Finally, I try to keep track of possibly breaking changes and new features in
[RELEASE-NOTES](https://github.com/c-blake/cligen/tree/master/RELEASE-NOTES.md).
