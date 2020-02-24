cligen: A Native API-Inferred Command-Line Interface Generator For Nim
======================================================================
This approach to CLIs was inspired by [Andrey Mikhaylenko's nice Python module
'argh'](https://pythonhosted.org/argh/) (in turn preceded by
[Plac](https://github.com/micheles/plac) ).
The basic idea is that native language proc signatures already encode/declare
almost everything needed to generate a CLI - names, types, and default values.
A little reflection/introspection then suffices to generate a parser-dispatcher
that translates `seq[string]` command input into calls to a wrapped proc.
In Nim, adding a CLI can be as easy as adding one line of code:
```nim
proc fun(foo=1,bar=2.0,baz="hi",verb=false,paths: seq[string]): int=
  ## Some existing API call
  result = 1        # Of course, real code would have real logic here
import cligen; dispatch(fun) # Whoa..Just 1 line??
```
Compile it to `fun` (e.g., `nim c fun.nim`) and then run `./fun --help`
to get a minimal (but not so useless!) help message:
```
Usage:
  fun [optional-params] [paths: string...]
Some existing API call
Options:
  -h, --help                    print this cligen-erated help
  --help-syntax                 advanced: prepend,plurals,..
  -f=, --foo=    int     1      set foo
  -b=, --bar=    float   2.0    set bar
  --baz=         string  "hi"   set baz
  -v, --verb     bool    false  set verb
```
Other invocations (`./fun --foo=2 --bar=2.7 ...`) all work as expected.
Default help tables work with automated "help to X" tools such as `complete -F
_longopt` in bash, `compdef _gnu_generic` in zsh, or the GNU `help2man`.

`cligen`-erated parsers accept **any unambiguous prefix** for long options.
In other words, long options can be as short as possible.  In yet other words,
hitting the TAB key to complete is unnecessary **if** the completion is unique.

When you want more specific help than `set foo`, just add parameter-keyed
metadata with Nim's association-list literals:
```nim
dispatch(fun, help = { "foo" : "the beginning", "bar" : "the rate" })
```
That's it.  No specification language or complex arg parsing APIs to learn.
If you aren't immediately sold, here is some more
[MOTIVATION](https://github.com/c-blake/cligen/tree/master/MOTIVATION.md).
Many CLI authors who have understood things this far can use `cligen` already.
Enter illegal commands or `--help` to get help messages to exhibit the mappings.

---

Most commands have some trailing variable length sequence of arguments like
the `paths` in the above example.  `cligen` automatically treats the first
non-defaulted `seq[T]` proc parameter as such an optional sequence.  `cligen`
applies the same basic string-to-native type converters/parsers used for option
values to such parameters.  If a proc parameter has no explicit default value,
it becomes required input, but the syntax for input is the same as for optional
values.  So, in the below
```nim
proc fun(myRequired: float, mynums: seq[int], foo=1, verb=false) =
  discard           # Of course, real code would have real logic here
when isMainModule:  # Preserve ability to `import api`/call from Nim
  import cligen; dispatch(fun)
```
the command-line user must give `--myRequired=something` somewhere to avoid an
error.  Non-option arguments must be parsable as `int` with whitespace stripped,
e.g. `./fun --myRequired=2.0 1 2 " -3"`.

---

`dispatchMulti` lets you expose two or more procs with subcommands a la `git` or
`nimble`. Each `[]` list in `dispatchMulti` is the argument list for each
sub-`dispatch`.  Tune command syntax and help strings in the same way as
`dispatch` as in:
```nim
proc foo(myRequired: int, mynums: seq[int], foo=1, verb=false) =
  ## Some API call
  discard
proc bar(yippee: int, myfloats: seq[float], verb=false) =
  ## Some other API call
  discard
when isMainModule:
  import cligen
  dispatchMulti([foo, help={"myRequired": "Need it!"}], [bar])
```
With the above in `cmd.nim`, CLI users can run `./cmd foo -m1` or
`./cmd bar -y10 1.0 2.0`.  `./cmd` or `./cmd --help` print brief help messages
while `./cmd help` prints a comprehensive message, and `./cmd SUBCMD --help`
or `./cmd help SUBCMD` print a message for just `SUBCMD` (e.g. `foo`|`bar`).

Like long option keys or enum values, **any unambiguous prefix** is accepted.
So, in the above `./cmd f -m1` would also work.  This is patterned after,
e.g. Mercurial, gdb, or gnuplot.  Additionally, long option keys can be spelled
flexibly, e.g.  `--dry-run` or `--dryRun`, much like Nim's style-insensitive
identifiers, but with extra insensitivity to so-called "kebab case".

---

Rather than dispatching to a proc and exiting, you can also initialize the
fields of an object/tuple from the command-line with `initFromCL` which has
the same keyword parameters as the most salient features of `dispatch`:
```nim
type App* = object
  srcFile*: string
  show*: bool
const dfl* = App(srcFile: "junk")  # set defaults != default for type

proc logic*(a: var App) = echo "app is: ", a

when isMainModule:
  import cligen
  var app = initFromCL(dfl, help = { "srcFile": "yadda yadda" })
  app.logic()  # Only --help/--version/parse errors cause early exit
```

More Controls For More Subtle Cases/More Picky CLI authors
==========================================================
You can manually control the short option for any parameter via the `short`
macro parameter:
```nim
dispatch(fun, short = { "bar" : 'r' }))
```
With that (and our first `fun` example), `"bar"` gets `'r'` while `"baz"`
gets `'b'` as short options.  To suppress some long option getting *any* short
option, specify `'\0'` as the value for its short key.  To suppress _all_
short options, give `short` a key of `""`.

---

The default exit protocol is (with boolean short-circuiting) `quit(int(result))
or (echo $result or discard; quit(0))`.  If `echoResult==true`, it's just
`echo $result; quit(0)`, while if `noAutoEcho==true` it's
`quit(int(result)) or (discard; quit(0))`.  The `or`s above are based on whether
the wrapped proc has a return type or `$` defined on the type.
So,
```nim
import editdistance, cligen   # gen CLI for Nim stdlib editDistance
dispatch(editDistanceASCII, echoResult=true)
```
makes a program to print edit distance between two required parameters.

If these exit protocols are inadequate then you may need to call `dispatchGen()`
and later call `try: dispatchFoo(someSeqString) except: discard` yourself.
This is all `dispatch` itself does.  ***Return*** _types and values_ of the
generated dispatcher match the wrapped proc. { Other parameters to generated
dispatchers are for internal use in `dispatchMulti` and probably don't matter to
you. }  A dispatcher raises 3 exception types: `HelpOnly`, `VersionOnly`,
`ParseError`.  These are hopefully self-explanatory.

---

If you want `cligen` to merge parameters from other sources like a `$CMD`
environment variable then you can redefine `mergeParams()` after `import cligen`
but before `dispatch`/`dispatchMulti`:
```nim
import cligen, os, strutils
proc mergeParams(cmdNames: seq[string],
                 cmdLine=commandLineParams()): seq[string] =
  let e = os.getEnv(toUpperAscii(join(cmdNames, "_")))  # $MULTI_(FOO|_BAR)
  if e.len > 0: parseCmdLine(e) & cmdLine else: cmdLine # See os.parseCmdLine
dispatchMulti([foo, short={"verb": 'v'}], [bar])
```
You can also just `include cligen/mergeCfgEnv` between `import cligen` and
`dispatch` to merge `${CMD_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}}/CMD` (with
Nim stdlib's `parsecfg` module) and then `$CMD` with `parseCmdLine` as shown
above, if that works for you.

Even More Controls and Details
==============================
After many feature requests `cligen` grew many knobs & levers.  First there are
more [DETAILS](https://github.com/c-blake/cligen/tree/master/DETAILS.md) on the
restrictions on wrappable procs and extending the parser to new argument types.
A good starting point for various advanced usages is the many examples in my
automated test suite:
  [test/](https://github.com/c-blake/cligen/tree/master/test/).
Then there is the documentation for the three main modules:
  [parseopt3](http://c-blake.github.io/cligen/parseopt3.html)
  [argcvt](http://c-blake.github.io/cligen/argcvt.html)
  [cligen](http://c-blake.github.io/cligen/cligen.html)
Finally, I try to keep track of possibly breaking changes and new features in
[RELEASE-NOTES](https://github.com/c-blake/cligen/tree/master/RELEASE-NOTES.md).
