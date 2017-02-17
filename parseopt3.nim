## This is a more featureful replacement for stdlib's parseopt2.  It should be
## drop-in compatible if ``requireSeparator=true`` is passed to ``getopt`` or
## ``initOptParser``.  Even with the default ``requireSeparator=false`` it is
## "mostly" the same - accepting yet not requiring users to use a separator.
##
## In addition to parseopt2 features, this version also provides flexibility
## over requiring separators between option keys and option values, as per
## traditional "Unix-like" command syntax, allows changing separator chars,
## fully supports short and long options with **and without** option values,
## and eases building "git-like" multiple command parsing.
##
## Supported command syntax is (here '=' and ':' may be any char in
## ``sepChars``):
##
## 1. short option bundles: ``-abx``  (where a, b, x ARE IN `shortBools`)
##
## 1a. bundles with one final value: ``-abc:Bar``, ``-abc=Bar``, ``-c Bar``,
## ``-abcBar`` (where ``c`` is NOT IN ``shortBools``)
##
## 2. long options with values: ``--foo:bar``, ``--foo=bar``, ``--foo bar``
## (where `foo` is NOT IN ``longBools``)
##
## 2a. long options without vals: ``--baz`` (where ``baz`` IS IN ``longBools``)
##
## 3. command parameters: everything else | anything after "--" or a stop word.
##
## The "key-value-separator-free" forms above require appropriate ``shortBools``
## and ``longBools`` lists for boolean flags.  Note that valueless-keys only
## make sense for boolean options.
##
## A notable subtlety is when the first character of an option value is one of
## ``sepChars``.  Even if ``requireSeparator`` is ``false``, passing such option
## values requires either A) putting the value in the next command parameter,
## as in ``"-c :"`` or B) prefixing the value with an element of ``sepChars``,
## as in ``-c=:`` or ``-c::``.
##
## To ease "nested" command-line parsing (such as with git where there may be
## early global options, a subcommand and later subcommand options), this parser
## also supports a set of "stop words" - special whole command parameters that
## prevent any subsequent parameters being interpreted as options.  This feature
## makes it easy to fully process a command line and then re-process its tail
## rather than mandating breaking out at a stop word with a manual test.  Stop
## words are basically just like the Unix "--" (which this parser also supports
## even if "--" is not in stopWords).  Such stop words (or "--") can still be
## the **values** to any options.  Only usage as a non-option command parameter
## acts to stop possible option-treatment of later parameters.

import os, strutils

type
  CmdLineKind* = enum         ## the detected command line token
    cmdEnd,                   ## end of command line reached
    cmdArgument,              ## argument detected
    cmdLongOption,            ## a long option ``--option`` detected
    cmdShortOption            ## a short option ``-c`` detected
  OptParser* =
      object of RootObj       ## this object implements the command line parser
    cmd: seq[string]          # command line being parsed
    pos: int                  # current command parameter to inspect
    moreShort: string         # carry over short flags to process
    optsDone: bool            # "--" has been seen
    shortBools: string        # 1-letter options not requiring optarg
    longBools: seq[string]    # long options not requiring optarg
    stopWords: seq[string]    # special literal parameters that act like "--"
    requireSep: bool          # require separator between option key & val
    sepChars: set[char]
    kind*: CmdLineKind        ## the detected command line token
    key*, val*: TaintedString ## key and value pair; ``key`` is the option
                              ## or the argument, ``value`` is not "" if
                              ## the option was given a value

proc initOptParser*(cmdline: seq[string] = commandLineParams(),
                    shortBools: string = nil,
                    longBools: seq[string] = nil,
                    requireSeparator=false,  # true imitates stdlib parseopt2
                    sepChars: string= "=:",
                    stopWords: seq[string] = @[]): OptParser =
  ## Initializes a command line parse. `cmdline` should not contain parameter 0,
  ## typically the program name.  If `cmdline` is not given, default to current
  ## program parameters.
  ##
  ## `shortBools` and `longBools` specify respectively one-letter and long
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
  result.cmd = @cmdline                 #XXX is @ necessary?  Does that copy?
  result.shortBools = shortBools
  result.longBools = longBools
  result.requireSep = requireSeparator
  for c in sepChars:
    result.sepChars.incl(c)
  result.stopWords = stopWords
  result.moreShort = ""
  result.optsDone = false

proc do_short(p: var OptParser) =
  p.kind = cmdShortOption
  p.val = nil
  p.key = p.moreShort[0..0]             # shift off first char as key
  p.moreShort = p.moreShort[1..^1]
  if p.moreShort.len == 0:              # param exhausted; advance param
    p.pos += 1
  if p.shortBools != nil and p.key in p.shortBools:     # no opt argument =>
    return                                              # continue w/same param
  if p.requireSep and p.moreShort[0] notin p.sepChars:  # No optarg in reqSep mode
    return
  if p.moreShort.len != 0:              # only advance if haven't already
    p.pos += 1
  if p.moreShort[0] in p.sepChars:      # shift off maybe-optional separator
    p.moreShort = p.moreShort[1..^1]
  if p.moreShort.len > 0:               # same param argument is trailing text
    p.val = p.moreShort
    p.moreShort = ""
    return
  if p.pos < p.cmd.len:                 # Empty moreShort; opt arg = next param
    p.val = p.cmd[p.pos]
    p.pos += 1
  elif p.shortBools != nil:
    echo "argument expected for option `", p.key, "` at end of params"

proc do_long(p: var OptParser) =
  p.kind = cmdLongOption
  p.val = nil
  let param = p.cmd[p.pos]
  p.pos += 1                            # always consume at least 1 param
  let sep = find(param, p.sepChars)     # only very first occurrence of delim
  if sep == 2:
    echo "Empty long option key at param", p.pos - 1, " (\"", param, "\")"
    p.key = nil
    return
  if sep > 2:
    p.key = param[2 .. sep-1]
    p.val = param[sep+1..^1]
    if p.longBools != nil and p.key in p.longBools:
      echo "Warning option `", p.key, "` does not expect an argument"
    return
  p.key = param[2..^1]                  # no sep; key is whole param past --
  if p.longBools != nil and p.key in p.longBools:
    return                              # No argument; done
  if p.requireSep:
    echo "Expecting option key-val separator :|= after `", p.key, "`"
    return
  if p.pos < p.cmd.len:                 # Take opt arg from next param
    p.val = p.cmd[p.pos]
    p.pos += 1
  elif p.longBools != nil:
    echo "argument expected for option `", p.key, "` at end of params"

proc next*(p: var OptParser) =
  if p.moreShort.len > 0:               #Step1: handle any remaining short opts
    do_short(p)
    return
  if p.pos >= p.cmd.len:                #Step2: end of params check
    p.kind = cmdEnd
    return
  if not p.cmd[p.pos].startsWith("-") or p.optsDone:  #Step3: non-option param
    p.kind = cmdArgument
    p.key = p.cmd[p.pos]
    p.val = nil
    if p.cmd[p.pos] in p.stopWords:     #Step4: check for stop word
      p.optsDone = true                 # should only hit Step3 henceforth
    p.pos += 1
    return
  if p.cmd[p.pos].startsWith("--"):     #Step5: "--*"
    if p.cmd[p.pos].len == 2:           # terminating "--" => pure arg mode
      p.optsDone = true                 # should only hit Step3 henceforth
      p.pos += 1                        # skip the "--" itself, unlike stopWords
      next(p)                           # do next one so each parent next()..
      return                            #..yields exactly 1 opt+arg|cmdarg
    do_long(p)
  else:                                 #Step6: "-" but not "--" => short opt
    if p.cmd[p.pos].len == 1:           #Step6a: simply "-" => non-option param
      p.kind = cmdArgument              #  {"-" often used to indicate "stdin"}
      p.key = p.cmd[p.pos]
      p.val = nil
      p.pos += 1
    else:                               #Step6b: maybe a block of short options
      p.moreShort = p.cmd[p.pos][1..^1] # slice out the initial "-"
      do_short(p)

proc optionNormalize*(s: string, wordSeparators="_-"): string {.noSideEffect.} =
  ## Normalizes option key `s`.
  ##
  ## That means to convert ALL BUT FIRST char to lower case and remove any
  ## chars in wordSeparators ('_' and '-') by default.
  result = newString(s.len)
  var wordSeps: set[char]
  for c in wordSeparators: wordSeps.incl(c)
  result[0] = s[0]
  var j = 1
  for i in 1..len(s) - 1:
    if s[i] in {'A'..'Z'}:
      result[j] = chr(ord(s[i]) + (ord('a') - ord('A')))
      inc j
    elif s[i] notin wordSeps:
      result[j] = s[i]
      inc j
  if j != s.len: setLen(result, j)

type
  GetoptResult* = tuple[kind: CmdLineKind, key, val: TaintedString]

iterator getopt*(cmdline=commandLineParams(), shortBools: string = nil,
                 longBools: seq[string] = nil, requireSeparator=true,
                 sepChars="=:", stopWords: seq[string] = @[]): GetoptResult =
  ## This is an convenience iterator for iterating over the command line.
  ## Parameters here are the same as for initOptParser.  Example:
  ## .. code-block:: nim
  ##   var filename = ""
  ##   for kind, key, val in getopt():
  ##     case kind
  ##     of cmdLongOption, cmdShortOption:
  ##       case key
  ##       of "help", "h": writeHelp()
  ##       of "version", "v": writeVersion()
  ##     else:              # must be non-option cmdArgument
  ##       filename = key
  ##   if filename == "": writeHelp()
  var p = initOptParser(cmdline, shortBools, longBools, requireSeparator,
                        sepChars, stopWords)
  while true:
    next(p)
    if p.kind == cmdEnd: break
    yield (p.kind, p.key, p.val)
