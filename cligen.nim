import macros, tables, parseopt3, strutils, os

proc toString(c: char): string =
  result = newStringOfCap(1)
  if c != '\0': result.add(c)

proc toStrSeq(strSeqInitializer: NimNode): seq[string] =
  result = newSeq[string]()
  for kid in strSeqInitializer[1]:
    result.add($kid)

proc formalParamExpand(fpars: NimNode, suppress: seq[string]= @[]): NimNode =
  # a,b,..,c:type [maybe=val] --> a:type, b:type, ..., c:type [maybe=val]
  result = newNimNode(nnkFormalParams)
  result.add(fpars[0])                                  # just copy ret value
  for declIx in 1 ..< len(fpars):
    let idefs = fpars[declIx]
    for i in 0 ..< len(idefs) - 3:
      if $idefs[i] notin suppress:
        result.add(newIdentDefs(idefs[i], idefs[^2]))
    if $idefs[^3] notin suppress:
      result.add(newIdentDefs(idefs[^3], idefs[^2], idefs[^1]))

proc formalParams(n: NimNode, suppress: seq[string]= @[]): NimNode =
  # Extract formal parameter list from the return value of .symbol.getImpl
  for kid in n:
    if kid.kind == nnkFormalParams:
      return formalParamExpand(kid, suppress)
  error "formalParams requires a proc argument."
  return nil

proc parseHelps(helps: NimNode): Table[string, string] =
  # Compute a table giving the help text for any parameter
  result = initTable[string, string]()
  for ph in helps:
      let p: string = (ph[1][0]).strVal
      let h: string = (ph[1][1]).strVal
      result[p] = h

proc parseShorts(shorts: NimNode): Table[string, char] =
  # Compute a table giving the user-specified short option for any parameter
  result = initTable[string, char]()
  for losh in shorts:
      let lo: string = (losh[1][0]).strVal
      let sh: char = char((losh[1][1]).intVal)
      result[lo] = sh

proc dupBlock(fpars: NimNode, posIx: int,
              userSpec: Table[string, char]): Table[string, char] =
  # Compute a table giving the short option for any long option, being
  # careful to only allow one such short option if the 1st letters of
  # two or more long options collide.
  result = initTable[string, char]()         # short option for param
  if "" in userSpec: return                  # Empty string key==>no short opts
  var used: set[char] = {}                   # used shorts; bit vector ok
  for lo, sh in userSpec:
    result[lo] = sh
    used.incl(sh)
  for i in 1 ..< len(fpars):                 # [0] is proc, not desired here
    if i == posIx: continue                  # positionals get no option char
    let parNm = $(fpars[i][0])
    let sh = parNm[0]                        # abbreviation is 1st character
    if sh notin used and parNm notin result: # still available
      result[parNm] = sh
      used.incl(sh)
  for k, v in result:
    if v == '\0': result.del(k)

proc collectComments(buf: var string, n: NimNode, depth: int = 0) =
  if n.len > 1:
    for kid in n: collectComments(buf, kid, depth + 1)
  else:
    if n.kind == nnkCommentStmt and depth < 5:
      if n.strVal != nil:
        buf.add(" ")
        buf.add(n.strVal)

proc findByName(parNm: string, fpars: NimNode): int =
  result = -1
  if len(parNm) == 0: return
  for i in 1 ..< len(fpars):
    if $fpars[i][0] == parNm:
      result = i
      break
  if result == -1:
    warning("specified positional argument `" & parNm & "` not found")

proc posIxGet(positional: NimNode, fpars: NimNode): int =
  ## Find the proc param to map to optional positional arguments of a command.
  if len(positional.strVal) > 0:
    result = findByName(positional.strVal, fpars)
    if result == -1:
      error("requested positional argument catcher " & positional.strVal &
            " is not in formal parameter list")
    return
  result = -1                     # No optional positional arg param yet found
  for i in 1 ..< len(fpars):
    let idef = fpars[i]           # 1st typed,non-defaulted seq; Allow override?
    if idef[1].kind != nnkEmpty and idef[2].kind == nnkEmpty and
       typeKind(getType(idef[1])) == ntySequence:
      if result != -1:            # Allow multiple seq[T]s via "--" separators?
        warning("cligen only supports one seq param for positional args; using"&
                " `" & $fpars[result][0] & "`, not `" & $fpars[i][0] & "`.")
      else:
        result = i

proc newParam(id: string, rhs: NimNode): NimNode =
    return newNimNode(nnkExprEqExpr).add(ident(id), rhs)

const helpTabOption*  = 0
const helpTabType*    = 1
const helpTabDefault* = 2
const helpTabDescrip* = 3

macro dispatchGen*(pro: typed, cmdName: string="", doc: string="",
                   help: typed= {}, short: typed= {}, usage: string
="${prelude}$command $args\n$doc  Options(opt-arg sep :|=|spc):\n$options$sep",
                   prelude = "Usage:\n  ", echoResult: bool = false,
                   requireSeparator: bool = false, sepChars = "=:",
                   helpTabColumnGap: int=2, helpTabMinLast: int=16,
                   helpTabRowSep: string="", helpTabColumns: seq[int] = @[
                    helpTabOption, helpTabType, helpTabDefault, helpTabDescrip],
                   stopWords: seq[string] = @[], positional = "",
                   argPre:seq[string]= @[], argPost:seq[string]= @[],
                   suppress:seq[string]= @[]): untyped =
  ## Generate a command-line dispatcher for proc `pro` with extra help `usage`.
  ## Parameters without defaults in the proc become mandatory command arguments
  ## while those with default values become command options.  Proc parameters
  ## and option keys are normalized so that command users may spell multi-word
  ## option keys flexibly as in ``--dry-Run``|``--dryrun``.  Each proc parameter
  ## type must have in-scope argParse and argHelp templates (argcvt.nim defines
  ## argParse/Help for many basic types).
  ##
  ## `help` is a seq[(paramNm,str)] of per-param help, eg. {"quiet":"be quiet"}.
  ## Very often, only these user-given help strings are needed for a decent CLI.
  ##
  ## `short` is a seq[(paramNm,char)] of per-parameter single-char option keys.
  ##
  ## Non-int return types are discarded since programs can only return integer
  ## exit codes (usually 1-byte) to OSes.  However, if `echoResult` is true
  ## then generated dispatchers echo the result of wrapped procs and return 0.
  ##
  ## If `requireSeparator` is true, both long and short options need an element
  ## of `sepChars` (":=" by default) before option values (if there are any).
  ##
  ## `stopWords` is a seq[string] of words beyond which ``-`` or ``--`` will no
  ## longer signify an option (like the common sole ``--`` command argument).
  ##
  ## `helpTabColumnGap` and `helpTabMinLast` control format parameters of the
  ## options help table, and `helpTabRowSep` ("" by default) separates rows.
  ## `helpTabColumns` selects columns to format and is a seq of some subset of
  ## `{ helpTabOption, helpTabType, helpTabDefault, helpTabDescrip }`, though
  ## only the final column in a help table row auto-word-wraps.
  ##
  ## By default, `cligen` maps the first non-defaulted seq[] proc parameter to
  ## any non-option/positional command args.  `positional` selects another.
  ##
  ## `argPre` & `argPost` are sources of cmdLine-like data, e.g. from a split
  ## environment variable value, applied pre/post the actual command line.
  ##
  ## `suppress` is a list of names of formal parameters to NOT include in the
  ## parsing/assigning system.  Such names are effectively pinned to whatever
  ## their default values are.

  let helps = parseHelps(help)
  #XXX Nim fails to access macro args in sub-scopes.  So `help` (`cmdName`...)
  #XXX needs either to accessed at top-level or assigned in a shadow local.
  let impl = pro.symbol.getImpl
  let fpars = formalParams(impl, toStrSeq(suppress))
  var cmtDoc: string = $doc
  if cmtDoc == nil or cmtDoc.len == 0:  # allow caller to override commentDoc
    collectComments(cmtDoc, impl)
    cmtDoc = strip(cmtDoc)
  let proNm = $pro                      # Name of wrapped proc
  let cName = if len($cmdName) == 0: proNm else: $cmdName
  let disNm = toNimIdent("dispatch" & $pro) # Name of dispatch wrapper
  let posIx = posIxGet(positional, fpars) #param slot for positional cmd args|-1
  let shOpt = dupBlock(fpars, posIx, parseShorts(short))
  var spars = copyNimTree(fpars)        # Create shadow/safe prefixed params.
  var mandatory = newSeq[int]()         # At the same time, build metadata on..
  var mandHelp = ""                     #..non-defaulted/mandatory parameters.
  for i in 1 ..< len(fpars):
    spars[i][0] = ident($(fpars[i][0]) & "cligenDispatcher") # unique suffix
    if fpars[i][2].kind == nnkEmpty:
      if i == posIx:                    # No initializer; Add @[]
        spars[posIx][2] = prefix(newNimNode(nnkBracket), "@")
      else:
        if fpars[i][1].kind == nnkEmpty:
          error("parameter `" & $(fpars[i][0]) &
                "` has neither a type nor a default value")
        mandatory.add(i)
        mandHelp &= " {" & $fpars[i][0] & ":" & $repr(fpars[i][1]) & "}"
  let posNoId = ident("posNo")          # positional arg number
  let docId = ident("doc")              # gen proc parameter
  let usageId = ident("usage")          # gen proc parameter
  let cmdLineId = ident("cmdline")      # gen proc parameter
  let helpId = ident("help")            # local help table var
  let HelpOnlyId = ident("HelpOnly")    # local just help exception
  let prefixId = ident("prefix")        # local help prefix param
  let subSepId = ident("subSep")        # sub cmd help separator
  let shortBoolId = ident("shortBool")  # local list of arg-free short opts
  let longBoolId = ident("longBool")    # local list of arg-free long opts
  let keyId = ident("key")              # local option key
  let valId = ident("val")              # local option val
  var callIt = newNimNode(nnkCall)      # call of wrapped proc in genproc
  callIt.add(pro)
  let htColGap = helpTabColumnGap
  let htMinLst = helpTabMinLast
  let htRowSep = helpTabRowSep
  let htCols   = helpTabColumns
  let prlude   = prelude

  proc initVars(): NimNode =            # init vars & build help str
    result = newStmtList()
    let tabId = ident("tab")            # local help table var
    result.add(quote do:
      var `tabId`: seq[array[0..3, string]] =
        @[ [ "--help, -?", "", "", "print this help message" ] ]
      var `shortBoolId`: string = "?"   # argHelp(..,bool,..) updates these
      var `longBoolId`: seq[string] = @[ "help" ])
    var args = "[optional-params]" & mandHelp &
               (if posIx != -1: " [" & $(fpars[posIx][0]) & "]" else: "")
    for i in 1 ..< len(fpars):
      let idef = fpars[i]
      let sdef = spars[i]
      result.add(newNimNode(nnkVarSection).add(sdef))     #Init vars
      callIt.add(newNimNode(nnkExprEqExpr).add(idef[0], sdef[0])) #Add to call
      if i notin mandatory and i != posIx:
        let parNm = $idef[0]
        let sh = toString(shOpt.getOrDefault(parNm))      #Add to perPar helpTab
        let defVal = sdef[0]
        let hlp=if parNm in helps: helps.getOrDefault(parNm) else: "set "&parNm
        result.add(quote do: argHelp(`tabId`, `defVal`, `parNm`, `sh`, `hlp`))
    result.add(quote do:                  # build one large help string
      let indentDoc = addPrefix(`prefixId`, `docId`)
      var `helpId`=`usageId` % [ "prelude", `prlude`, "doc", indentDoc,
                     "command", `cName`, "args", `args`, "options",
                     addPrefix(`prefixId` & "  ",
                               alignTable(`tabId`, 2*len(`prefixId`) + 2,
                                          `htColGap`, `htMinLst`, `htRowSep`,
                                          `htCols`)),
                     "sep", `subSepId` ]
      if `helpId`[^1] != '\l':            # ensure newline @end of help
        `helpId` &= "\n"
      if len(`prefixId`) > 0:             # to indent help in a multicmd context
        `helpId` = addPrefix(`prefixId`, `helpId`) )

  proc defOptCases(): NimNode =
    result = newNimNode(nnkCaseStmt).add(quote do: optionNormalize(`keyId`))
    result.add(newNimNode(nnkOfBranch).add(
      newStrLitNode("help"),newStrLitNode("?")).add(
        quote do: stderr.write(`helpId`); raise newException(`HelpOnlyId`,"")))
    for i in 1 ..< len(fpars):                # build per-param case clauses
      if i == posIx: continue                 # skip variable len positionals
      if i in mandatory: continue             # skip mandator arguments
      let parNm  = $fpars[i][0]
      let lopt   = optionNormalize(parNm)
      let apCall = newCall("argParse", spars[i][0], keyId, valId, helpId)
      if parNm in shOpt:                      # both a long and short option
        let parShOpt = $shOpt.getOrDefault(parNm)
        result.add(newNimNode(nnkOfBranch).add(
          newStrLitNode(lopt), newStrLitNode(parShOpt)).add(apCall))
      else:                                   # only a long option
        result.add(newNimNode(nnkOfBranch).add(newStrLitNode(lopt)).add(apCall))
    result.add(newNimNode(nnkElse).add(quote do:
      argRet(1, "Bad option: \"" & `keyId` & "\"\n" & `helpId`)))

  proc defNonOpt(): NimNode =
    result = newStmtList()
    if posIx != -1 or len(mandatory) > 0:     # code to parse non-option args
      result.add(newNimNode(nnkCaseStmt).add(quote do: postInc(`posNoId`)))
      for i, ix in mandatory:
        let hlp=newStrLitNode("non-option " & $i & " (" & $(fpars[ix][0]) & ")")
        result[0].add(newNimNode(nnkOfBranch).add(newIntLitNode(i)).add(
          newCall("argParse", spars[ix][0], hlp, keyId, helpId)))
      if posIx != -1:                         # mandatory + optional positionals
        let posId = spars[posIx][0]
        let tmpId = ident("tmp" & $posId)
        result[0].add(newNimNode(nnkElse).add(quote do:
          var rewind = false                  #Ugly machinery is so tmp=pos[0]..
          if len(`posId`) == 0:               #..type inference works.
            `posId`.setLen(1)
            rewind = true
          var `tmpId` = `posId`[0]
          argParse(`tmpId`, "positional $" & $`posNoId`, `keyId`,"positional\n")
          if rewind: `posId`.setLen(0)
          `posId`.add(`tmpId`)))
      else:                                   # only mandatory (no positionals)
        result[0].add(newNimNode(nnkElse).add(quote do:
          argRet(1, "Optional positional arguments unexpected\n" & `helpId`)))
    else:
      result.add(quote do:
       argRet(1,`proNm` & " does not expect non-option arguments\n" & `helpId`))

  let argPreP=argPre; let argPostP=argPost  #XXX ShouldBeUnnecessary
  proc callParser(): NimNode =
    result = quote do:
      var exitCode = 0
      if `argPreP` != nil and len(`argPreP`) > 0:
        exitCode += parser(`argPreP`)
      exitCode += parser()
      if `argPostP` != nil and len(`argPostP`) > 0:
        exitCode += parser(`argPostP`)
      if exitCode != 0:
        return exitCode

  let echoResultP = echoResult              #XXX ShouldBeUnnecessary
  proc callWrapped(): NimNode =
    if fpars[0].kind == nnkEmpty:           # pure proc/no return type
      result = quote do:
        `callIt`; return 0
    else:                                   # convertible-to-int return type
      result = quote do:
         if `echoResultP`:
           echo `callIt`; return 0
         else:
           when compiles(int(`callIt`)): return `callIt`
           else: discard `callIt`; return 0

  let iniVar=initVars(); let optCases=defOptCases(); let nonOpt=defNonOpt()
  let callPrs=callParser(); let callWrapd=callWrapped() #XXX ShouldBeUnnecessary
  result = quote do:
    from os     import commandLineParams
    from argcvt import argRet, argParse, argHelp, alignTable, addPrefix, postInc
    from parseopt3 import getopt, cmdLongOption, cmdShortOption, optionNormalize
    import strutils # import join, `%`
    proc `disNm`(`cmdLineId`: seq[string] = commandLineParams(),
                 `docId`: string = `cmtDoc`, `usageId`: string = `usage`,
                 `prefixId`="", `subSepId`=""): int =
      type `HelpOnlyId` = object of Exception
      `iniVar`
      {.push hint[XDeclaredButNotUsed]: off.}
      proc parser(args=`cmdLineId`): int =
        var `posNoId` = 0
        for kind,`keyId`,`valId` in
            getopt(args, `shortBoolId`, `longBoolId`,
                   `requireSeparator`, `sepChars`, `stopWords`):
          case kind
              of cmdLongOption, cmdShortOption:
                `optCases`
              else:
                `nonOpt`
      {.pop.}
      try:
        `callPrs`
        `callWrapd`
      except `HelpOnlyId`:
        discard
  when defined(printDispatch): echo repr(result)  # maybe print generated code

macro dispatch*(pro: typed, cmdName: string="", doc: string="",
                help: typed = { }, short: typed = { }, usage: string
="${prelude}$command $args\n$doc  Options(opt-arg sep :|=|spc):\n$options$sep",
                prelude = "Usage:\n  ", echoResult: bool = false,
                requireSeparator: bool = false, sepChars = "=:",
                helpTabColumnGap=2, helpTabMinLast=16, helpTabRowSep="",
                helpTabColumns = @[ helpTabOption, helpTabType, helpTabDefault,
                                    helpTabDescrip ],
                stopWords: seq[string] = @[], positional = "",
                argPre:seq[string] = @[], argPost:seq[string] = @[],
                suppress:seq[string] = @[]): untyped =
  ## A convenience wrapper to both generate a command-line dispatcher and then
  ## call quit(said dispatcher); Usage is the same as the dispatchGen() macro.
  result = newStmtList()
  result.add(newCall(
    "dispatchGen", pro, cmdName, doc, help, short, usage, prelude, echoResult,
    requireSeparator, sepChars, helpTabColumnGap, helpTabMinLast, helpTabRowSep,
    helpTabColumns, stopWords, positional, argPre, argPost, suppress))
  result.add(newCall("quit", newCall("dispatch" & $pro)))

macro dispatchMulti*(procBrackets: varargs[untyped]): untyped =
  ## A convenience wrapper to both generate a multi-command dispatcher and then
  ## call quit(said dispatcher); procBrackets=arg lists for dispatchGen(), e.g,
  ## dispatchMulti([ foo, short={"dryRun": "n"} ], [ bar, doc="Um" ]).
  result = newStmtList()
  for p in procBrackets:
    var c = newCall("dispatchGen")
    copyChildrenTo(p, c)
    c.add(newParam("prelude", newStrLitNode("")))
    result.add(c)
  let fileParen = lineinfo(procBrackets)  # Infer multi-cmd name from lineinfo
  let xOpPar = rfind(fileParen, ".nim(") - 1
  let srcBase = newStrLitNode(if xOpPar < 0: "??" else: fileParen[0 .. xOpPar])
  let arg0Id = ident("arg0")
  let restId = ident("rest")
  let dashHelpId = ident("dashHelp")
  let multiId = ident("multi")
  let subcmdsId = ident("subcmds")
  var multiDef = newStmtList()
  multiDef.add(quote do:
    import os
    proc `multiId`(subcmd: seq[string]) =
      let n = subcmd.len
      let `arg0Id` = if n > 0: subcmd[0] else: "help"
      let `restId`: seq[string] = if n > 1: subcmd[1..<n] else: @[ ])
  var cases = multiDef[0][1][^1].add(newNimNode(nnkCaseStmt).add(arg0Id))
  var helps = (quote do:
        echo "Usage:  This is a multiple-dispatch cmd.  Usage is like"
        echo "  $1 subcommand [subcommand-opts & args]" % [ `srcBase` ]
        echo "where subcommand syntaxes are as follows:\n"
        let `dashHelpId` = @[ "--help" ])
  var cnt = 0
  for p in procBrackets:
    inc(cnt)
    let disp = "dispatch_" & $p[0]
    cases[^1].add(newNimNode(nnkOfBranch).add(newStrLitNode($(p[0]))).add(
      newCall("quit", newCall(disp, restId))))
    let sep = if cnt < len(procBrackets): "\n" else: ""
    helps.add(newNimNode(nnkDiscardStmt).add(
      newCall(disp, dashHelpId, newParam("prefix", newStrLitNode("  ")),
              newParam("subSep", newStrLitNode(sep)))))
  cases[^1].add(newNimNode(nnkElse).add(helps))
  result.add(multiDef)
  result.add(quote do:
    var `subcmdsId`: seq[string] = @[ ])
  for p in procBrackets:
    result.add(newCall("add", subcmdsId, newStrLitNode($p[0])))
  result.add(newCall("dispatch", multiId, newParam("stopWords", subcmdsId),
                     newParam("cmdName", srcBase), newParam("usage", quote do:
    "${prelude}$command {subcommand}\nwhere {subcommand} is one of:\n  " &
      join(`subcmdsId`, " ") & "\n" &
      "Run top-level cmd with the subcmd \"help\" to get full help text.\n" &
      "Run a subcommand with --help to see only help for that.")))
  when defined(printMultiDisp): echo repr(result)  # maybe print generated code
