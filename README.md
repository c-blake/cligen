# cligen: A Native API-Inferred Command-Line Interface Generator For Nim

This approach to CLIs was inspired by Andrey Mikhaylenko's Python
[argh](https://pythonhosted.org/argh/) (
[Click](https://github.com/pallets/click/) became more popular).
The core idea is that proc signatures encode almost everything needed to
generate CLIs - names, types, and default values.  Reflection then suffices to
generate parser-dispatchers translating `seq[string]` command input into calls
to a wrapped proc.  In Nim, adding a CLI can be as easy as:
```nim
proc fun(foo=1,bar=2.0,baz="hi",verb=false,paths: seq[string]):int=
  ## An API call doc comment
  result = 1      # Of course, real code would have real work here
import cligen; dispatch(fun) # Whoa..Just 1 line??
```
Compile it to `fun` (e.g., `nim c fun.nim`) and then run `./fun --help`
to get a minimal (but not so useless!) help message:
```
Usage:
  fun [optional-params] [paths: string...]
An API call doc comment
Options:
  -h, --help                    print this cligen-erated help
  --help-syntax                 advanced: prepend,plurals,..
  -f=, --foo=    int     1      set foo
  -b=, --bar=    float   2.0    set bar
  --baz=         string  "hi"   set baz
  -v, --verb     bool    false  set verb
```
That's it!  No specification language/complex arg parsing API/Nim pragma tags
to learn.  Installing can be as simple as `nimble install cligen` or even just
`git clone <thisRepo>` and `nim c --path:whereYouClonedTo myProgram.nim`.  If
you aren't sold already, here is more
[MOTIVATION](https://github.com/c-blake/cligen/tree/master/MOTIVATION.md).

The `help` column is filled with generic `set foo` placeholders by default, but
you can override it using parameter-keyed association-list literals:
```nim
dispatch(fun, help = { "foo": "the beginning", "bar": "the rate" })
```
The same goes for the `short` versions of the CLI arguments.  More on that in
the "Common Overrides" section below.

Other invocations (`./fun --foo 2 -b=2.7 --baz:"ho"...`) work as expected.

Default help tables work with automated "help to X" tools such as `complete -F
_longopt` in bash, `compdef _gnu_generic` in zsh, or the GNU `help2man` (e.g.
`help2man -N ./fun|man /dev/stdin`).

Nim CLI authors who have understood things this far can mostly use `cligen`
already.  Enter illegal commands or `--help` to get help messages to exhibit
the mappings or `--help-syntax`/`--helps` to see more on that.  Out of the box,
`cligen` supports string-to-native conversion for most elementary Nim types
(ints, floats, enums, etc.), as well as `seq`s, `set`s, `HashSet`s of them.

### CLusage: Token Match, Render, Trailing Args, Required Params

`cligen`-erated parsers accept **any unambiguous prefix** for long options.
In other words, long options can be as short as possible.  In yet other words,
hitting the TAB key to complete is unnecessary **if** the completion is unique.
This is patterned after, e.g. gnuplot, gdb, Vim ex-commands, etc.  Long options
can also be **spelled flexibly**, e.g. `--dry-run`|`--dryRun`, like Nim's
style-insensitive identifiers, but with extra "kebab-case-insensitivity".
(The exact spelling of the key in `help` controls the look of printed help.
Layout details like column spacing and help colorization are controlled [by a
CL user config file](https://github.com/c-blake/cligen/tree/master/configs).
Here are screenshots of an example
[night-theme](https://raw.githubusercontent.com/c-blake/cligen/master/screenshots/dirqHelpNight.png)
and
[day-theme](https://raw.githubusercontent.com/c-blake/cligen/master/screenshots/dupsHelpDay.png)).

---

Most commands have some trailing variable length sequence of arguments like
the `paths` in the above example.  `cligen` automatically treats the first
non-defaulted `seq[T]` proc parameter as such an optional sequence.  `cligen`
applies the same basic string-to-native type converters/parsers used for option
values to such parameters.

---

If a proc parameter has no **explicit** default value (via `=`) then it becomes
required, but the input syntax is the same as for optional values.  So, in
```nim
proc fun(myRequired: float, mynums: seq[int], foo=1, verb=false) =
  discard          # Of course, real code would have real work here
when isMainModule: # Preserve ability to `import api`/call from Nim
  import cligen; dispatch(fun)
```
the command-line user must give `--myRequired=something` somewhere to avoid an
error.  Non-option arguments must be parsable as `int` with whitespace stripped,
e.g. `./fun --myRequired=2.0 1 2 " -3"`.

### Custom Parameter Types or Parsing

While `cligen` supports basic Nim types out of the box (strings, numbers, enums,
sequences and sets of such, etc.), the parsing/printing system is *extensible*.
This is done via in-`dispatch` scope `argParse` & `argHelp` overloads for types.
(These could almost be `parseType` & `$`; CLusers!=CLauthors & other integration
 requirements motivate two separate names.)  A simple example:
```nim
import std/times
proc foo(i = 42, d = now()): void = echo d

when isMainModule:
  import cligen/argcvt, cligen
  proc argParse(dst: var DateTime, dfl: DateTime,
                a: var ArgcvtParams): bool =
    try: dst = times.parse(a.val, "yyyyMMdd")
    except TimeParseError:
      echo "bad DateTime: ", a.val; return false
    return true

  proc argHelp(dfl: DateTime, a: var ArgcvtParams): seq[string]=
    @[a.argKeys, "DateTime", getDateStr(dfl)]

  dispatch foo, help={"i": "favorite number", "d": "birthday"}
```
These two "argument IO" procs take a shared coordination parameter for argument
metadata (more fully documented in `cligen/argcvt.nim`).  As just one simple
e.g., `a.parNm` is the name of the parameter being parsed.  While not useful
ordinarily, this can be used to parse the same Nim type differently (based on
the name), detect when CLusers alter parameters from defaults, count uses, etc.

This same mechanism can ***override existing*** `cligen/argcvt` parser/helpers if
the built-ins are not what you want.  Consulting `cligen/argcvt` for examples is
a good idea.

### Subcommands, dispatch to object init

`dispatchMulti` lets you expose two or more procs with subcommands a la `git` or
`nimble`. Each `[]` list in `dispatchMulti` is the argument list for each
sub-`dispatch`.  Tune command syntax and help strings in the same way as
`dispatch` as in:
```nim
proc foo(myRequired: int, mynums: seq[int], foo=1, verb=false) =
  ## Some API call
  discard
proc bar(yippee: int, myFlts: seq[float], verb=false) = discard
  ## Some other API call
when isMainModule:
  import cligen
  dispatchMulti([foo, help={"myRequired": "Need it!"}], [bar])
```
With the above in `cmd.nim`, CLI users can run `./cmd foo -m1` or
`./cmd bar -y10 1.0 2.0`.  `./cmd` or `./cmd --help` print brief help messages
while `./cmd help` prints a comprehensive message, and `./cmd SUBCMD --help`
or `./cmd help SUBCMD` print a message for just `SUBCMD` (e.g. `foo`|`bar`).

Like long option keys or enum value names, subcommand names can also be ***any
unambiguous prefix and are case-kebab-insensitive***.  So, `./cmd f-O -m1` would
also work above.

---

Rather than dispatching to a proc and exiting, you can also initialize the
***fields of an object/tuple*** from the command-line with `initFromCL` which
has the same keyword parameters as the most salient features of `dispatch`:
```nim
type App* = object
  srcFile*: string
  show*: bool
const dfl* = App(srcFile: "junk")  # set defaults!=default for type

proc logic*(a: var App) = echo "app is: ", a

when isMainModule:
  import cligen
  var app = initFromCL(dfl, help = { "srcFile": "yadda yadda" })
  app.logic() # Only --help/--version/parse errors cause early exit
```

### Common Overrides, Exit Protocol, Config File/Environment Vars

You can manually control the short option for any parameter via the `short`
macro parameter:
```nim
dispatch(fun, short = { "bar" : 'r' })
```
If you'd like to define `short` or `help` parameters outside of a `dispatch`
call, you need an explicit conversion to a `Table`:
```nim
import cligen
from std/tables import toTable
const
  Help =  { "foo": "the beginning", "bar": "the rate" }.toTable()
  Short = { "foo": 'f', "bar": 'r'}.toTable()
proc fun(foo = 1, bar = 2, baz = "hi") = discard
dispatch(fun, help = Help, short = Short)
```
With that `"bar"` gets `'r'` while `"baz"` gets `'b'` as short options.
To suppress some long option getting *any* short option, specify `'\0'`
as the value for its short key.  To suppress _all_ short options, give 
`short` a key of `""`.

To suppress API parameters in the CLI, pass `suppress = @[ "apiParam", ... ]`.
To suppress presence only in the help message use `help = { "apiParam":
"CLIGEN-NOHELP" }`.  Pass `implicitDefault=@["apiParam",...]` to let the CLI wrapper
default API parameter values with no explicit initialization to the Nim default
for a type.

---

The default exit protocol is (with boolean short-circuiting) `quit(int(result))
or (echo $result or discard; quit(0))`.  If `echoResult==true`, it's just
`echo $result; quit(0)`, while if `noAutoEcho==true` it's `quit(int(result)) or
(discard; quit(0))`.  The `or`s above are based on whether the wrapped proc has
a return type or `$` defined on the type.  So,
```nim
import editdistance, cligen   # gen CLI for Nim stdlib editDistance
dispatch(editDistanceASCII, echoResult=true)
```
makes a program to print edit distance between two required parameters while
without `echoResult` it would be in the shell `$?` variable.

If these exit protocols are inadequate then you may need to call `dispatchGen()`
and later call `try: dispatchFoo(someSeqString) except: discard` yourself.
This is all `dispatch` itself does.  ***Return*** _types and values_ of the
generated dispatcher match the wrapped proc. { Other parameters to generated
dispatchers are for internal use in `dispatchMulti` and probably don't matter to
you. }  A dispatcher raises 3 exception types: `HelpOnly`, `VersionOnly`,
`ParseError`.  These are hopefully self-explanatory.

---

If you want `cligen` to merge parameters from other sources, like a per-program
config file and/or `$CMD` environment variable, then you can redefine
`mergeParams()` after `import cligen` but before `dispatch`/`dispatchMulti`:
```nim
import cligen, os, strutils # multi foo/multi bar are like subcommand example
proc mergeParams(cmdNames: seq[string],
                 cmdLine=commandLineParams()): seq[string] =
  let e = os.getEnv(toUpperAscii(join(cmdNames, "_")))  # $MULTI_(FOO|BAR)
  if e.len > 0: parseCmdLine(e) & cmdLine else: cmdLine # See os.parseCmdLine
dispatchMulti([foo, short={"verb": 'v'}], [bar])
```
You can also just `include cligen/mergeCfgEnv` between `import cligen` and
`dispatch` to merge `${CMD_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}}/CMD` (with
Nim stdlib's `parsecfg` module) and then `$CMD` with `parseCmdLine` as above.

`cligen` programs look for `${XDG_CONFIG_HOME:-$HOME/.config}/cligen`, e.g.
[~/.config/cligen/config](https://github.com/c-blake/cligen/wiki/Example-Config-File)
which allows command-line end users to tweak colors, layout, syntax, and usage
help templates.

### Restrictions

 1. Can only wrap basic funcs/procs -- no `auto|var` types, generics, etc.
   
 2. Param types used must have argParse, argHelp in scope (including generic
    parameters like the `T` in `seq[T]`).

 3. No param of a wrapped proc can be named "help".  (Name collision!)

### Even More Controls and Details

After many feature requests `cligen` grew many knobs & levers.  Look at the
many examples (which I tried to name suggestively) in the automated test suite:
  [test/](https://github.com/c-blake/cligen/tree/master/test/)
for starting points of various advanced usages.

Then there is [The Wiki](https://github.com/c-blake/cligen/wiki) and generated
documentation for the three main modules:
  [parseopt3](http://c-blake.github.io/cligen/cligen/parseopt3.html)
  [argcvt](http://c-blake.github.io/cligen/cligen/argcvt.html)
  [cligen](http://c-blake.github.io/cligen/cligen.html)
Finally, I try to keep track of possibly breaking changes and new features in
[RELEASE-NOTES](https://github.com/c-blake/cligen/tree/master/RELEASE-NOTES.md).
