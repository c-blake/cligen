## This module provides a Nim command line parser that is mostly API compatible
## with the Nim standard library parseopt (and the code derives from that).
## It supports one convenience iterator over all command line options and some
## lower-level features.
## Supported command syntax (here ``=|:`` may be any char in ``sepChars``):
##
## 1. short option bundles: ``-abx``  (where a, b, x *are in* ``shortNoVal``)
##
## 1a. bundles with one final value: ``-abc:Bar``, ``-abc=Bar``, ``-c Bar``,
## ``-abcBar`` (where ``c`` is *not in* ``shortNoVal``)
##
## 2. long options with values: ``--foo:bar``, ``--foo=bar``, ``--foo bar``
##    (where ``foo`` is *not in* ``longNoVal``)
##
## 2a. long options without vals: ``--baz`` (where ``baz`` is in ``longNoVal``)
##
## 3. command parameters: everything else | anything after "--" or a stop word.
##
## The above is a *superset* of usual POSIX command syntax - it should accept
## any POSIX-inspired input, but it also accepts more forms/styles. (Note that
## POSIX itself is not super strict about this part of the standard.  See:
## http://pubs.opengroup.org/onlinepubs/009604499/basedefs/xbd_chap12.html)
##
## When ``optionNormalize(key)`` is used, command authors provide command users
## additional flexibility to ``--spell_multi-word_options -aVarietyOfWays
## --as-Per_User-Preference``.  This is similar to Nim style-insensitive
## identifier syntax, but by default allows dash ('-') as well as underscore
## ('_') word separation.
##
## The "separator free" forms above require appropriate ``shortNoVal`` and
## ``longNoVal`` lists to designate option keys that take no value (as well
## as ``requireSeparator == false``).  If such lists are empty, the user must
## use separators when providing any value.
##
## A notable subtlety is when the first character of an option value is one of
## ``sepChars``.  Even if ``requireSeparator`` is ``false``, passing such option
## values requires either A) putting the value in the next command parameter,
## as in ``"-c :"`` or B) prefixing the value with an element of ``sepChars``,
## as in ``-c=:`` or ``-c::``.  Both choices fit into common quoting styles.
## It seems likely a POSIX-habituated end-user's second guess (after ``"-c:"``
## errored out with "argument expected") would just work as they expected.
## POSIX itself encourages authors & users to use the ``"-c :"`` form anyway.
## This small deviation lets this parser accept valid invocations with the
## original Nim option parser command syntax (with the same semantics), easing
## transition.
##
## To ease "nested" command-line parsing (such as with "git" where there may be
## early global options, a subcommand and later subcommand options), this parser
## also supports a set of "stop words" - special whole command parameters that
## prevent subsequent parameters being interpreted as options.  This feature
## makes it easy to fully process a command line and then re-process its tail
## rather than mandating breaking out at a stop word with a manual test.  Stop
## words are basically just like a POSIX "--" (which this parser also supports -
## even if "--" is not in ``stopWords``).  Such stop words (or "--") can still
## be the **values** of option keys with no effect.  Only usage as a non-option
## command parameter acts to stop possible option-treatment of later parameters.
##
## To facilitate syntax for operations beyond simple assignment, ``opChars`` is
## a set of chars that may prefix an element of ``sepChars``. The ``sep`` member
## of ``OptParser`` is the actual separator used for the current option, if any.
## E.g, a user entering "="  causes ``sep == "="`` while entering "+=" gets
## ``sep == "+="``, and "+/-+=" gets ``sep == "+/-+="``.

import std/[os, strutils, critbits]

proc optionNormalize*(s: string, wordSeparators="_-"): string {.noSideEffect.} =
  ## Normalizes option key ``s`` to allow command syntax to be style-insensitive
  ## in a similar way to Nim identifier syntax.
  ##
  ## Specifically this means to convert *all but the first* char to lower case
  ## and remove chars in ``wordSeparators`` ('_' and '-') by default.  This way
  ## users can type "command --my-opt-key" or "command --myOptKey" and so on.
  ##
  ## Example:
  ##
  ## .. code-block:: nim
  ##   for kind, key, val in p.getopt():
  ##     case kind
  ##     of cmdLongOption, cmdShortOption:
  ##       case optionNormalize(key)
  ##       of "myoptkey", "m": doSomething()
  result = newString(s.len)
  if s.len == 0: return
  var wordSeps: set[char]   # compile a set[char] from ``wordSeparators``
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
  ## Use ``cb`` to find normalized long form of ``key``. Return empty string if
  ## ambiguous or unchanged string on no match.
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
    cmdLongOption,            ## a long option ``--option`` detected
    cmdShortOption,           ## a short option ``-c`` detected
    cmdError                  ## error in primary option syntax usage
  OptParser* = object of RootObj  ## object to implement the command line parser
    cmd*: seq[string]         ## command line being parsed
    pos*: int                 ## current command parameter to inspect
    off*: int                 ## current offset in cmd[pos] for short key block
    optsDone*: bool           ## "--" has been seen
    shortNoVal*: set[char]    ## 1-letter options not requiring optarg
    longNoVal*: CritBitTree[string] ## long options not requiring optarg
    stopWords*: CritBitTree[string] ## special literal params acting like "--"
    requireSep*: bool         ## require separator between option key & val
    sepChars*: set[char]      ## all the chars that can be valid separators
    opChars*: set[char]       ## all chars that can prefix a sepChar
    longPfxOk*: bool          ## true means unique prefix is ok for longOpts
    stopPfxOk*: bool          ## true means unique prefix is ok for stopWords
    sep*: string              ## actual string separating key & value
    message*: string          ## message to display upon cmdError
    kind*: CmdLineKind        ## the detected command line token
    key*, val*: TaintedString ## key and value pair; ``key`` is the option
                              ## or the argument, ``value`` is not "" if
                              ## the option was given a value

proc initOptParser*(cmdline: seq[string] = commandLineParams(),
                    shortNoVal: set[char] = {}, longNoVal: seq[string] = @[],
                    requireSeparator=false, sepChars={'=',':'},
                    opChars: set[char] = {}, stopWords: seq[string] = @[],
                    longPfxOk=true, stopPfxOk=true): OptParser =
  ## Initializes a parse. ``cmdline`` should not contain parameter 0, typically
  ## the program name.  If ``cmdline`` is not given, default to current program
  ## parameters.
  ##
  ## ``shortNoVal`` and ``longNoVal`` specify respectively one-letter and long
  ## option keys that do *not* take arguments.
  ##
  ## If ``requireSeparator==true``, then option keys&values must be separated
  ## by an element of ``sepChars`` (default ``{'=',':'}``) in short or long
  ## option contexts.  If ``requireSeparator==false``, the parser understands
  ## that only non-NoVal options will expect args and users may say ``-aboVal``
  ## or ``-o Val`` or ``--opt Val`` { as well as the `-o:Val|--opt=Val`
  ## separator style which always works }.
  ##
  ## If ``opChars`` is not empty then those characters before the ``:|==``
  ## separator are reported in the ``.sep`` field of an element parse.  This
  ## allows "incremental" syntax like ``--values+=val``.
  ##
  ## If ``longPfxOk`` then unique prefix matching is done for long options.
  ## If ``stopPfxOk`` then unique prefix matching is done for stop words
  ## (usually subcommand names).
  ##
  ## Parameters following either "--" or any literal parameter in ``stopWords``
  ## are never interpreted as options.
  result.cmd = cmdline
  result.shortNoVal = shortNoVal
  for s in longNoVal:   #Take normalizer param vs. hard-coding optionNormalize?
    if s.len > 0: result.longNoVal.incl(optionNormalize(s), s)
  result.requireSep = requireSeparator
  result.sepChars = sepChars
  result.opChars = opChars
  {.push warning[ProveField]: off.}
  for w in stopWords:
    if w.len > 0: result.stopWords.incl(optionNormalize(w), w)
  {.pop.}
  result.longPfxOk = longPfxOk
  result.stopPfxOk = stopPfxOk
  result.off = 0
  result.optsDone = false

proc initOptParser*(cmdline: string): OptParser =
  ## Initializes option parses with cmdline.  Splits cmdline in on spaces and
  ## calls `initOptParser(openarray[string])`.  Should use a proper tokenizer.
  if cmdline == "": # backward compatibility
    return initOptParser(commandLineParams())
  else:
    return initOptParser(cmdline.split)

proc doShort(p: var OptParser) =
  proc cur(p: OptParser): char =
    if p.off < p.cmd[p.pos].len: result = p.cmd[p.pos][p.off]
    else: result = '\0'
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
    doShort(p)
    return
  if p.pos >= p.cmd.len:                #Step2: end of params check
    p.kind = cmdEnd
    return
  if not p.cmd[p.pos].startsWith("-") or p.optsDone:  #Step3: non-option param
    p.kind = cmdArgument
    p.key = p.cmd[p.pos]
    p.val = ""
    let k = p.stopWords.lengthen(optionNormalize(p.cmd[p.pos]), p.stopPfxOk)
    if k in p.stopWords:                #Step4: chk for stop word
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
  ## An convenience iterator for iterating over the given OptParser object.
  ## Example:
  ##
  ## .. code-block:: nim
  ##   var p = initOptParser("--left --debug:3 -l=4 -r:2")
  ##   for kind, key, val in p.getopt():
  ##     case kind
  ##     of cmdArgument:
  ##       filename = key
  ##     of cmdLongOption, cmdShortOption:
  ##       case key
  ##       of "help", "h": writeHelp()
  ##       of "version", "v": writeVersion()
  ##     of cmdEnd: assert(false) # cannot happen
  ##   if filename == "":
  ##     # no filename has been given, so we show the help:
  ##     writeHelp()
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
    ## This is an convenience iterator for iterating over the command line.
    ## Parameters here are the same as for initOptParser.  Example:
    ## See above for a more detailed example
    ##
    ## .. code-block:: nim
    ##   for kind, key, val in getopt():
    ##     # this will iterate over all arguments passed to the cmdline.
    ##     continue
    ##
    var p = initOptParser(cmdline, shortNoVal, longNoVal, requireSeparator,
                          sepChars, opChars, stopWords)
    while true:
      next(p)
      if p.kind == cmdEnd: break
      yield (p.kind, p.key, p.val)
{.pop.}
