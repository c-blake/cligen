##[ This module provides a Nim command line parser that is mostly API compatible
with the Nim standard library parseopt (and the code derives from that).  It
supports a convenience iterator over all command line options & some lower-level
features.  Default supported command syntax (here `=|:` may be any char in
`sepChars`):

1. short option bundles: `-abx`  (where a, b, x *are in* `shortNoVal`)

1a. bundles with one final value: `-abc:Bar`, `-abc=Bar`, `-c Bar`, `-abcBar`
   (where `c` is *not in* `shortNoVal`)

2. long options with values: `--foo:bar`, `--foo=bar`, `--foo bar` (where `foo`
   is *not in* `longNoVal`)

2a. long options without vals: `--baz` (where `baz` is in `longNoVal`)

3. command parameters: everything else | anything after "--" or a stop word.

The above is a *superset* of usual POSIX command syntax - it should accept most
POSIX-inspired input, but also accepts more forms/styles. (POSIX is iffy about
this http://pubs.opengroup.org/onlinepubs/009604499/basedefs/xbd_chap12.html)

When `optionNormalize(key)` is used, command authors provide command users
additional flexibility to `--spell_multi-word_options -aVarietyOfWays
--as-Per_User-Preference`.  This is similar to Nim style-insensitive identifier
syntax, but by default allows dash ('-') as well as underscore ('_') word
separation.

"Separator-free" forms above require appropriate `shortNoVal` and `longNoVal`
lists to designate option keys that take no value (as well as `requireSeparator
== false`).  If such lists are empty, users must use separators to give values.

A notable subtlety is when the first char of an option value is in `sepChars`.
Even if `requireSeparator` is `false`, passing such option values requires
either A) putting the value in the next command parameter, as in `"-c :"` or B)
prefixing the value with an element of `sepChars`, as in `-c=:` or `-c::`.  Both
choices fit into common quoting styles.  It seems likely a POSIX-habituated
end-user's second guess (after `"-c:"` errored out with "argument expected")
would just work as they expected.  POSIX itself encourages authors & users to
use the `"-c :"` form anyway.  This small deviation lets this parser accept
valid invocations with the original Nim option parser command syntax (with the
same semantics), easing cross-compatibility.

To ease "nested" command-line parsing (such as with "git" where there may be
early global options, a subcommand and later subcommand options), this parser
also supports a set of "stop words" - special whole command parameters that
prevent subsequent parameters being interpreted as options.  This feature makes
it easy to fully process a command line and then re-process its tail rather than
mandating breaking out at a stop word with a manual test.  I.e., stop words are
like a POSIX "--" (which this parser also does - even if "--" is not in
`stopWords`).  Such stop words (or "--") can still be **values** of option keys
with no effect.  Only usage of a stop word as a non-option command parameter
acts to stop possible option-treatment of later parameters.

To facilitate syntax for operations beyond simple assignment, `opChars` is a set
of chars that may prefix an element of `sepChars`. The `sep` member of
`OptParser` is any actual separator used for the current option.  E.g, a user
entering "="  causes `sep == "="` while entering "+=" gets `sep == "+="`, and
"+/-+=" gets `sep == "+/-+="`.

This module also enables run-time selection of modes of varying strictness to
support either user-preferences or enforcing various scripting styles.  This is
done with a `set[SyntaxFlag]` type to control key-value separation with symbol
tables, whether various kinds of abbreviation are allowed, whether the first
`cmdArgument` ends treatment as possible options (like stop words), whether flag
folding is allowed, and whether short options are even allowed at all. ]##

import std/[os, strutils, critbits]

proc optionNormalize*(s: string, wordSeparators="_-"): string {.noSideEffect.} =
  ## Normalizes option key `s` to allow command syntax to be style-insensitive
  ## in a similar way to Nim identifier syntax.
  ## 
  ## Specifically this means to convert *all but the first* char to lower case
  ## and remove chars in `wordSeparators` ('_' and '-') by default.  This way
  ## users can type "command --my-opt-key" or "command --myOptKey" and so on.
  ## 
  ## .. code-block:: nim
  ##   for kind, key, val in p.getopt():
  ##     case kind
  ##     of cmdLongOption, cmdShortOption:
  ##       case optionNormalize(key)
  ##       of "myoptkey", "m": doSomething()
  result = newString(s.len)
  if s.len == 0: return
  var wordSeps: set[char]   # compile a set[char] from `wordSeparators`
  for c in wordSeparators:
    wordSeps.incl(c)
  result[0] = s[0]
  var j = 1
  for i in 1..len(s) - 1:
    if s[i] in {'A'..'Z'}:
      result[j] = chr(ord(s[i]) + (ord('a') - ord('A')))
      inc j
    elif s[i] notin wordSeps:
      result[j] = s[i]
      inc j
  if j != s.len:
    setLen(result, j)

{.push warning[ProveField]: off.}
proc valsWithPfx*[T](cb: CritBitTree[T], key: string): seq[T] =
  for v in cb.valuesWithPrefix(optionNormalize(key)): result.add(v)

proc lengthen*[T](cb: CritBitTree[T], key: string, prefixOk=false): string =
  ##[ Use `cb` to find normalized long form of `key`. Return empty string if
  ambiguous or unchanged string on no match. ]##
  let n = optionNormalize(key)
  if not prefixOk:
    return n
  var ks: seq[string]
  for k in cb.keysWithPrefix(n): ks.add(k)
  if ks.len == 1:
    return ks[0]
  if ks.len > 1:    # Can still have an exact match if..
    for k in ks:    #..one long key fully prefixes another,
      if k == n:    #..like "help" prefixing "help-syntax".
        return n
  if ks.len > 1:    #No exact prefix-match above => ambiguity
    return ""       #=> of-clause that reports ambiguity in .msg.
  return n  #ks.len==0 => case-else clause suggests spelling in .msg.
{.pop.}

when not declared(TaintedString):
  type TaintedString* = string
{.push warning[Deprecated]: off.}
type
  CmdLineKind* = enum         ## the detected command line token
    cmdEnd,                   ## end of command line reached
    cmdArgument,              ## argument detected
    cmdLongOption,            ## a long option `--option` detected
    cmdShortOption,           ## a short option `-c` detected
    cmdError                  ## error in primary option syntax usage
  SyntaxFlag* = enum          ## Command-Line Option Syntax Flags
    sfRequireSep,             ##[true=>require `sepChars` element between option
      key&val.  Parser knows that both long/short non-NoVal expect args so space
      separators also work.]##
    sfLongPfxOk,              ## true=>unique prefix is ok for longOpts
    sfStopPfxOk,              ## true=>unique prefix is ok for stopWords
    sfArgEndsOpts,            ## true=>disallow options after 1st non-option arg
    sfOnePerArg,              ## true=>disallow -a -b- => -ab bool flag folding
    sfNoShort                 ## true=>run-time disallow short (vs. compTime-"")
  OptParser* = object of RootObj  ## object to implement the command line parser
    cmd*: seq[string]         ## command line being parsed
    pos*: int                 ## current command parameter to inspect
    off*: int                 ## current offset in cmd[pos] for short key block
    optsDone*: bool           ## "--" has been seen
    shortNoVal*: set[char]    ## 1-letter options not requiring optarg
    longNoVal*: CritBitTree[string] ## long options not requiring optarg
    stopWords*: CritBitTree[string] ## special literal params acting like "--"
    flags*: set[SyntaxFlag]   ## flags for all option syntax variations
    sepChars*: set[char]      ## all the chars that can be valid separators
    opChars*: set[char]       ## all chars that can prefix a sepChar
    sep*: string              ## actual string separating key & value
    message*: string          ## message to display upon cmdError
    kind*: CmdLineKind        ## the detected command line token
    key*, val*: TaintedString ## key and value pair; `key` is the option
                              ## or the argument, `value` is not "" if
                              ## the option was given a value

# Some back.compat field checkers; OptParser(..) construction NOT back.compat.
proc requireSep*(p:OptParser):bool = sfRequireSep in p.flags ## Chk sfRequireSep
proc longPfxOk*(p: OptParser):bool = sfLongPfxOk  in p.flags ## Chk sfLongPfxOk
proc stopPfxOk*(p: OptParser):bool = sfStopPfxOk  in p.flags ## Chk sfStopPfxOk
    
const laxFlags*: set[SyntaxFlag] = {}

proc initOptParser*(cmdline: seq[string] = commandLineParams(), flags=laxFlags,
 shortNoVal: set[char] = {}, longNoVal: seq[string] = @[], sepChars={'=',':'},
 opChars: set[char] = {}, stopWords: seq[string] = @[]): OptParser =
  ##[Initializes a parse. `cmdline` should not contain parameter 0, typically
  the program name.  If `cmdline` is not given, default to current program
  parameters.
  
  `flags` - any non-lax syntax flags, such as `sfRequireSep`.
  
  `shortNoVal` and `longNoVal` specify respectively one-letter and long option
  keys that do *not* take arguments (needed if separator not needed).
  
  If `opChars` is not empty then those char before the `:|==` separator are
  reported in the `.sep` field of an element parse.  This allows "incremental"
  syntax like `--values+=val`.
  
  Parameters following either "--" or any literal parameter in `stopWords` are
  never interpreted as options.]##
  result.cmd = cmdline
  result.flags = flags
  result.shortNoVal = shortNoVal
  for s in longNoVal:   #Take normalizer param vs. hard-coding optionNormalize?
    if s.len > 0: result.longNoVal.incl(optionNormalize(s), s)
  result.sepChars = sepChars
  result.opChars = opChars
  {.push warning[ProveField]: off.}
  for w in stopWords:
    if w.len > 0: result.stopWords.incl(optionNormalize(w), w)
  {.pop.}
  result.off = 0
  result.optsDone = false

proc initOptParser*(cmdline: seq[string] = commandLineParams(),
 shortNoVal:set[char] = {}, longNoVal:seq[string] = @[], requireSeparator=false,
 sepChars={'=',':'}, opChars: set[char] = {}, stopWords: seq[string] = @[],
 longPfxOk=true, stopPfxOk=true): OptParser = # {.deprecated.} WARNS ON NON-USE
  ## DEPRECATED LEGACY INTERFACE (that evolved from only `requireSeparator`).
  var flags: set[SyntaxFlag]
  if requireSeparator: flags.incl sfRequireSep
  if longPfxOk: flags.incl sfLongPfxOk
  if stopPfxOk: flags.incl sfStopPfxOk
  initOptParser cmdline,flags, shortNoVal,longNoVal, sepChars,opChars, stopWords

proc initOptParser*(cmdline: string): OptParser =
  ##[ Initializes option parses with cmdline.  Splits cmdline in on spaces and
  calls `initOptParser(seq[string])`.  Should use a proper tokenizer.]##
  if cmdline == "": # backward compatibility
    return initOptParser(commandLineParams(), laxFlags)
  else:
    return initOptParser(cmdline.split, laxFlags)

proc cur(p: OptParser): char =
  if p.off < p.cmd[p.pos].len: result = p.cmd[p.pos][p.off]
  else: result = '\0'

proc doShort(p: var OptParser) =
  if sfNoShort in p.flags:
    p.message = "Short options are run-time disallowed at `" & p.key & "`"
    p.kind = cmdError; return
  p.kind = cmdShortOption
  p.val = ""
  p.key = $p.cur; p.off += 1            # shift off first char as key
  if p.cur in p.opChars or p.cur in p.sepChars:
    let mark = p.off
    while p.cur != '\0' and p.cur notin p.sepChars and p.cur in p.opChars:
      p.off += 1
    if p.cur in p.sepChars:             #This may set p.val="" w/sepChar&NoData
      p.sep = p.cmd[p.pos][mark..p.off] #..but since "--string=''" shows up this
      p.val = p.cmd[p.pos][p.off+1..^1] #..way, we consider it an "Ok" sitch..As
      p.pos += 1                        #..a byproduct, "--string=" is also Ok.
      p.off = 0
      return
    else:                               # Was just an opChars-starting value
      p.off = mark
  if p.key[0] in p.shortNoVal:          # No explicit val, but that is ok
    if p.off == p.cmd[p.pos].len:
      p.off = 0
      p.pos += 1
    return
  if p.requireSep:
    p.message = "Expecting option key-val separator :|= after `" & p.key & "`"
    p.kind = cmdError
    return
  if p.cmd[p.pos].len - p.off > 0:
    p.val = p.cmd[p.pos][p.off .. ^1]
    p.pos += 1
    p.off = 0
    return
  if p.pos < p.cmd.len - 1:             # opt val = next param
    p.val = p.cmd[p.pos + 1]
    p.pos += 2
    p.off = 0
    return
  p.val = ""
  p.off = 0
  p.pos += 1

proc doLong(p: var OptParser) =
  p.kind = cmdLongOption
  p.val = ""
  let param = p.cmd[p.pos]
  p.pos += 1                            # always consume at least 1 param
  let sep = find(param, p.sepChars)     # only very first occurrence of delim
  if sep > 2:
    var op = sep
    while op > 2 and param[op-1] in p.opChars:
      dec(op)
    p.key = param[2 .. op-1]
    p.sep = param[op .. sep]
    p.val = param[sep+1..^1]
    return
  p.key = param[2..^1]                  # no sep; key is whole param past "--"
  let k = p.longNoVal.lengthen(optionNormalize(p.key), p.longPfxOk)
  if k in p.longNoVal:
    return                              # No argument; done
  if p.requireSep:
    p.message = "Expecting option key-val separator :|= after `" & p.key & "`"
    p.kind = cmdError
    return
  if p.pos < p.cmd.len:                 # Take opt arg from next param
    p.val = p.cmd[p.pos]
    p.pos += 1
  elif p.longNoVal.len != 0:
    p.val = ""
    p.pos += 1

{.push warning[ProveField]: off.}
proc next*(p: var OptParser) =
  p.sep = ""
  if p.off > 0:                         #Step1: handle any remaining short opts
    if sfOnePerArg in p.flags:
      p.kind = cmdError
      p.message = "> 1 option per command parameter, after `" & p.key & "`"
      return
    else: doShort(p)
    return
  if p.pos >= p.cmd.len:                #Step2: end of params check
    p.kind = cmdEnd
    return
  if p.optsDone or not p.cmd[p.pos].startsWith("-"):  #Step3: non-option param
    p.kind = cmdArgument
    p.key = p.cmd[p.pos]
    p.val = ""
    let k = p.stopWords.lengthen(optionNormalize(p.cmd[p.pos]), p.stopPfxOk)
    if sfArgEndsOpts in p.flags or k in p.stopWords:  #Step4: chk for stopping
      p.optsDone = true                 # should only hit Step3 henceforth
    p.pos += 1
    return
  if p.cmd[p.pos].startsWith("--"):     #Step5: "--*"
    if p.cmd[p.pos].len == 2:           # terminating "--" => pure param mode
      p.optsDone = true                 # should only hit Step3 henceforth
      p.pos += 1                        # skip the "--" itself, unlike stopWords
      next(p)                           # do next one so each parent next()..
      return                            #..yields exactly 1 opt+arg|cmdparam
    doLong(p)
  else:                                 #Step6: "-" but not "--" => short opt
    if p.cmd[p.pos].len == 1:           #Step6a: simply "-" => non-option param
      p.kind = cmdArgument              #  {"-" often used to indicate "stdin"}
      if sfArgEndsOpts in p.flags: p.optsDone = true
      p.key = p.cmd[p.pos]
      p.val = ""
      p.pos += 1
    else:                               #Step6b: maybe a block of short options
      p.off = 1                         # skip the initial "-"
      doShort(p)
{.pop.}

type
  GetoptResult* = tuple[kind: CmdLineKind, key, val: TaintedString]

iterator getopt*(p: var OptParser): GetoptResult =
  ## A convenience iterator for iterating over the given OptParser object.  E.g.
  ##
  ## .. code-block:: nim
  ##   var filenames: seq[string] = @[]
  ##   var p = initOptParser("--left --debug:3 -l=4 -r:2")
  ##   for kind, key, val in p.getopt():
  ##     case kind
  ##     of cmdArgument: filenames.add key
  ##     of cmdLongOption, cmdShortOption:
  ##       case key
  ##       of "help", "h": writeHelp()
  ##       of "version", "v": writeVersion()
  ##       else: quit("unknown option key " & key, 2)
  ##     of cmdEnd: assert(false) # cannot happen
  ##     of cmdError:  quit(p.message, 3)
  ##   if filenames.len == 0: quit("no filename given", 4)
  p.pos = 0
  while true:
    next(p)
    if p.kind == cmdEnd: break
    yield (p.kind, p.key, p.val)

when declared(paramCount):
  iterator getopt*(cmdline=commandLineParams(), shortNoVal: set[char] = {},
                   longNoVal: seq[string] = @[], requireSeparator=false,
                   sepChars={'=', ':'}, opChars: set[char] = {},
                   stopWords: seq[string] = @[]): GetoptResult =
    ##[This is an convenience iterator for iterating over the command line.
    Parameters here are the same as for `initOptParser`.  See `(var OptParser)`
    overload for an example.]##
    var p = initOptParser(cmdline, shortNoVal, longNoVal, requireSeparator,
                          sepChars, opChars, stopWords)
    while true:
      next(p)
      if p.kind == cmdEnd: break
      yield (p.kind, p.key, p.val)
{.pop.}
