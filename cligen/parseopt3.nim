## This module provides a Nim command line parser that is mostly API compatible
## with the Nim standard library parseopt (and the code derives from that).
## It supports one convenience iterator over all command line options and some
## lower-level features.
## Supported command syntax (here ``=`` | ``:`` may be any char in ``sepChars``):
##
## 1. short option bundles: ``-abx``  (where a, b, x *are in* `shortNoVal`)
##
## 1a. bundles with one final value: ``-abc:Bar``, ``-abc=Bar``, ``-c Bar``,
## ``-abcBar`` (where ``c`` is *not in* ``shortNoVal``)
##
## 2. long options with values: ``--foo:bar``, ``--foo=bar``, ``--foo bar``
## (where ``foo`` is *not in* ``longNoVal``)
##
## 2a. long options without vals: ``--baz`` (where ``baz`` *is in* ``longNoVal``)
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
## To facilitate syntax for operations beyond simple assignment, ``opChars`` is a
## set of chars that may prefix an element of ``sepChars``.  The ``sep`` member
## of ``OptParser`` is the actual separator used for the current option, if any.
## E.g, a user entering "="  causes ``sep == "="`` while entering "+=" gets
## ``sep == "+="``, and "+/-+=" gets ``sep == "+/-+="``.

import os, strutils

type
  CmdLineKind* = enum         ## the detected command line token
    cmdEnd,                   ## end of command line reached
    cmdArgument,              ## argument detected
    cmdLongOption,            ## a long option ``--option`` detected
    cmdShortOption            ## a short option ``-c`` detected
  OptParser* =
      object of RootObj       ## this object implements the command line parser
    cmd*: seq[string]         # command line being parsed
    pos*: int                 # current command parameter to inspect
    off*: int                 # current offset into cmd[pos] for short key block
    optsDone*: bool           # "--" has been seen
    shortNoVal*: set[char]    # 1-letter options not requiring optarg
    longNoVal*: seq[string]   # long options not requiring optarg
    stopWords*: seq[string]   # special literal parameters that act like "--"
    requireSep*: bool         # require separator between option key & val
    sepChars*: set[char]      # all the chars that can be valid separators
    opChars*: set[char]       # all chars that can prefix a sepChar
    sep*: string              ## actual string separating key & value
    kind*: CmdLineKind        ## the detected command line token
    key*, val*: TaintedString ## key and value pair; ``key`` is the option
                              ## or the argument, ``value`` is not "" if
                              ## the option was given a value

proc ERR(x: varargs[string, `$`]) = stderr.write(x); stderr.write("\n")

proc initOptParser*(cmdline: seq[string] = commandLineParams(),
                    shortNoVal: set[char] = {},
                    longNoVal: seq[string] = @[],
                    requireSeparator=false,  # true imitates old parseopt2
                    sepChars={'=',':'}, opChars: set[char] = {},
                    stopWords: seq[string] = @[]): OptParser =
  ## Initializes a command line parse. `cmdline` should not contain parameter 0,
  ## typically the program name.  If `cmdline` is not given, default to current
  ## program parameters.
  ##
  ## `shortNoVal` and `longNoVal` specify respectively one-letter and long
  ## option keys that do _not_ take arguments.
  ##
  ## If `requireSeparator` is true, then option keys & values must be separated
  ## by an element of sepChars ('='|':' by default) in either short or long
  ## option contexts.  If requireSeparator==false, the parser understands that
  ## only non-bool options will expect args and users may say ``-aboVal`` or
  ## ``-o Val`` or ``--opt Val`` [ as well as the ``-o:Val``|``--opt=Val`` style
  ## which always works ].
  ##
  ## Parameters following either "--" or any literal parameter in stopWords are
  ## never interpreted as options.
  if cmdline == @[]:
    result.cmd = commandLineParams()
    return
  result.cmd = cmdline
  result.shortNoVal = shortNoVal
  result.longNoVal = longNoVal
  result.requireSep = requireSeparator
  result.sepChars = sepChars
  result.opChars = opChars
  result.stopWords = stopWords
  result.off = 0
  result.optsDone = false

proc initOptParser*(cmdline: string): OptParser =
  ## Initializes option parses with cmdline.  Splits cmdline in on spaces and
  ## calls initOptParser(openarray[string]).  Should use a proper tokenizer.
  if cmdline == "": # backward compatibility
    return initOptParser(seq[string](@[]))
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
    if p.cur in p.sepChars:
      if p.off > p.cmd[p.pos].len - 2:
        ERR "no data following sepChar"; return
      p.sep = p.cmd[p.pos][mark..p.off]
      p.val = p.cmd[p.pos][p.off+1..^1]
      p.pos += 1
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
    ERR "Expecting option key-val separator :|= after `", p.key, "`"
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
  ERR "argument expected for option `", p.key, "` at end of params"

proc doLong(p: var OptParser) =
  p.kind = cmdLongOption
  p.val = ""
  let param = p.cmd[p.pos]
  p.pos += 1                            # always consume at least 1 param
  let sep = find(param, p.sepChars)     # only very first occurrence of delim
  if sep == 2:
    ERR "Empty long option key at param", p.pos - 1, " (\"", param, "\")"
    p.key = ""
    return
  if sep > 2:
    var op = sep
    while op > 2 and param[op-1] in p.opChars:
      dec(op)
    p.key = param[2 .. op-1]
    p.sep = param[op .. sep]
    p.val = param[sep+1..^1]
    return
  p.key = param[2..^1]                  # no sep; key is whole param past "--"
  if p.longNoVal != @[] and p.key in p.longNoVal:
    return                              # No argument; done
  if p.requireSep:
    ERR "Expecting option key-val separator :|= after `", p.key, "`"
    return
  if p.pos < p.cmd.len:                 # Take opt arg from next param
    p.val = p.cmd[p.pos]
    p.pos += 1
  elif p.longNoVal != @[]:
    ERR "argument expected for option `", p.key, "` at end of params"

proc next*(p: var OptParser) =
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
    if p.cmd[p.pos] in p.stopWords:     #Step4: check for stop word
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

proc optionNormalize*(s: string, wordSeparators="_-"): string {.noSideEffect.} =
  ## Normalizes option key `s` to allow command syntax to be style-insensitive
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

type
  GetoptResult* = tuple[kind: CmdLineKind, key, val: TaintedString]

iterator getopt*(p: var OptParser): GetoptResult =
  ## This is an convenience iterator for iterating over the given OptParser object.
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
