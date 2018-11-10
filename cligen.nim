import macros, tables, cligen/parseopt3, strutils, os
type HelpOnly*    = object of Exception
type VersionOnly* = object of Exception
type ParseError*  = object of Exception

proc toString(c: char): string =
  ## creates a string from char `c`
  result = newStringOfCap(1)
  if c != '\0': result.add(c)

proc toStrLitNode(n: NimNode): NimNode =
  ## creates a string literal node from a char literal NimNode
  result = newNimNode(nnkStrLit)
  result.strVal = toString(chr(n.intVal))

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
  return nil                #not-reached

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

proc dupBlock(fpars: NimNode, posIx: int, hlpCh: NimNode,
              userSpec: Table[string, char]): Table[string, char] =
  # Compute a table giving the short option for any long option, being
  # careful to only allow one such short option if the 1st letters of
  # two or more long options collide.
  result = initTable[string, char]()         # short option for param
  if "" in userSpec: return                  # Empty string key==>no short opts
  var used: set[char]={ chr(hlpCh.intVal) }  # used shorts; bit vector ok
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
    if n.kind == nnkCommentStmt and depth < 4:
      if n.strVal.len != 0:
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

proc postInc*(x: var int): int =
  ## Similar to post-fix `++` in C languages: yield initial val, then increment
  result = x
  inc(x)

proc delItem*[T](x: var seq[T], item: T): int =
  result = find(x, item)
  if result >= 0:
    x.del(Natural(result))

type Version* = tuple[longOpt: string, output: string]

const dflUsage = "${prelude}$command $args\n" &
                 "$doc  Options(opt-arg sep :|=|spc):\n" &
                 "$options$sep"

macro dispatchGen*(pro: typed, cmdName: string = "", doc: string = "",
                   help: typed = {}, short: typed = {}, usage: string=dflUsage,
                   prelude="Usage:\n  ", echoResult: bool = false,
                   requireSeparator: bool = false, sepChars = {'=', ':'},
                   opChars={'+','-','*','/','%', '@',',', '.','&','^','~','|'},
                   helpTabColumnGap: int = 2, helpTabMinLast: int = 16,
                   helpTabRowSep: string = "", helpTabColumns: seq[int] = @[
                    helpTabOption, helpTabType, helpTabDefault, helpTabDescrip],
                   stopWords: seq[string] = @[], positional = "",
                   argPre: seq[string] = @[], argPost: seq[string] = @[],
                   suppress: seq[string] = @[], shortHelp = 'h',
                   implicitDefault: seq[string] = @[], mandatoryHelp="REQUIRED",
                   mandatoryOverride: seq[string] = @[], delimit=",",
                   version: Version=("",""), noAutoEcho: bool=false): untyped =
  ## Generate a command-line dispatcher for proc `pro` with extra help `usage`.
  ## Parameters without defaults in the proc become mandatory command arguments
  ## while those with default values become command options.  Proc parameters
  ## and option keys are normalized so that command users may spell multi-word
  ## option keys flexibly as in ``--dry-Run``|``--dryrun``.  Each proc parameter
  ## type must have in-scope argParse and argHelp procs (argcvt.nim defines
  ## argParse/Help for many basic types, set[T], seq[T], etc.).
  ##
  ## `help` is a {(paramNm,str)} of per-param help, eg. {"quiet":"be quiet"}.
  ## Very often, only these user-given help strings are needed for a decent CLI.
  ##
  ## `short` is a {(paramNm,char)} of per-parameter single-char option keys.
  ##
  ## Non-int return types are discarded since programs can only return integer
  ## exit codes (usually 1-byte) to OSes.  However, if `echoResult` is true then
  ## `dispatch` & `multiDispatch` echo the result of wrapped procs, returning 0.
  ## (Technically, dispatch callers not `dispatchGen` implement this parameter.)
  ##
  ## If `requireSeparator` is true, both long and short options need an element
  ## of `sepChars` before option values (if there are any).  Any series of chars
  ## in `opChars` may prefix an element of `sepChars` as in `parseopt3`.
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
  ## By default, `cligen` maps the first non-defaulted `seq[]` proc parameter
  ## to any non-option/positional command args.  `positional` selects another.
  ##
  ## `argPre` & `argPost` are sources of cmdLine-like data, e.g. from a split
  ## environment variable value, applied pre/post the actual command line.
  ##
  ## `suppress` is a list of formal parameter names to NOT include in the
  ## parsing/assigning system.  Such names are effectively pinned to whatever
  ## their default values are.
  ##
  ## `shortHelp` is a char to use for a short option key analogue of --help.
  ##
  ## `implicitDefault` is a list of formal parameter names allowed to default
  ## to the Nim default value for a type, rather than becoming mandatory, even
  ## when they are missing an explicit initializer. `mandatoryHelp` is how the
  ## default value appears in help messages for mandatory parameters.
  ##
  ## `mandatoryHelp` is the default value string in help tables for required
  ## parameters.  `mandatoryOverride` is a list of strings indicating parameter
  ## names which override mandatory-ness of anything else.
  ##
  ## `delimit` decides delimiting conventions for aggregate types like `set`s
  ## or `seq`s by assigning to `ArgcvtParams.delimit`.  Such delimiting is
  ## implemented by `argParse`/`argHelp`, and so is very user overridable.
  ## See `argcvt` documentation for details on the default implementation.
  ##
  ## `version` is a `Version` 2-tuple (longOpt for version, version string)
  ## which defines how a CLI user may dump the version of a program.  If you
  ## want to provide a short option, add a `"version":'v'` entry to `short`.

  let helps = parseHelps(help)
  #XXX Nim fails to access macro args in sub-scopes.  So `help` (`cmdName`...)
  #XXX needs either to be accessed at top-level or assigned in a shadow local.
  when compiles(pro.getImpl):
    let impl = pro.getImpl
  else:
    let impl = pro.symbol.getImpl
  let fpars = formalParams(impl, toStrSeq(suppress))
  var cmtDoc: string = $doc
  if cmtDoc.len == 0:                   # allow caller to override commentDoc
    collectComments(cmtDoc, impl)
    cmtDoc = strip(cmtDoc)
  let proNm = $pro                      # Name of wrapped proc
  let cName = if len($cmdName) == 0: proNm else: $cmdName
  when compiles(ident("dispatch" & $pro)):  # Name of dispatch wrapper
    let disNm = ident("dispatch" & $pro)
  elif compiles(!("dispatch" & $pro)):
    let disNm = !("dispatch" & $pro)
  else:
    let disNm = toNimIdent("dispatch" & $pro)
  let posIx = posIxGet(positional, fpars) #param slot for positional cmd args|-1
  let shOpt = dupBlock(fpars, posIx, shortHelp, parseShorts(short))
  var spars = copyNimTree(fpars)        # Create shadow/safe suffixed params.
  var dpars = copyNimTree(fpars)        # Create default suffixed params.
  var mandatory = newSeq[int]()         # At the same time, build metadata on..
  let implDef = toStrSeq(implicitDefault)
  let mandOvr = toStrSeq(mandatoryOverride)
  for i in 1 ..< len(fpars):            #..non-defaulted/mandatory parameters.
    dpars[i][0] = ident($(fpars[i][0]) & "ParamDefault")   # unique suffix
    spars[i][0] = ident($(fpars[i][0]) & "ParamDispatch")  # unique suffix
    if fpars[i][2].kind == nnkEmpty:
      if i == posIx:                    # No initializer; Add @[]
        spars[posIx][2] = prefix(newNimNode(nnkBracket), "@")
      else:
        if fpars[i][1].kind == nnkEmpty:
          error("parameter `" & $(fpars[i][0]) &
                "` has neither a type nor a default value")
        if $fpars[i][0] notin implDef:
          mandatory.add(i)
  let posNoId = ident("posNo")          # positional arg number
  let keyCountId = ident("keyCount")    # positional arg number
  let docId = ident("doc")              # gen proc parameter
  let usageId = ident("usage")          # gen proc parameter
  let cmdLineId = ident("cmdline")      # gen proc parameter
  let vsnOpt = $version[0]              # Need string lits here for CL parse
  let vsnSh = if vsnOpt in shOpt: $shOpt[vsnOpt] else: ""
  let vsnStr = version[1]               # value must just work in stdout.write
  let prefixId = ident("prefix")        # local help prefix param
  let subSepId = ident("subSep")        # sub cmd help separator
  let pId = ident("p")                  # local OptParser result handle
  let mandId = ident("mand")            # local list of mandatory parameters
  let mandInFId = ident("mandInForce")  # local list of mandatory parameters
  let apId = ident("ap")                # ArgcvtParams
  var callIt = newNimNode(nnkCall)      # call of wrapped proc in genproc
  callIt.add(pro)
  let htColGap = helpTabColumnGap
  let htMinLst = helpTabMinLast
  let htRowSep = helpTabRowSep
  let htCols   = helpTabColumns
  let prlude   = prelude; let mandHelp = mandatoryHelp
  let shortHlp = shortHelp; let delim = delimit

  proc initVars(): NimNode =            # init vars & build help str
    result = newStmtList()
    let tabId = ident("tab")            # local help table var
    result.add(quote do:
      var `apId`: ArgcvtParams
      `apId`.mand = `mandHelp`
      `apId`.delimit = `delim`
      let shortH = $(`shortHlp`)
      var `mandId`: seq[string] = @[ ]
      var `mandInFId` = true
      var `tabId`: TextTab =
        @[ @[ "-" & shortH & ", --help", "", "", "write this help to stdout" ] ]
      `apId`.shortNoVal = { shortH[0] } # argHelp(bool) updates
      `apId`.longNoVal = @[ "help" ])   # argHelp(bool) appends
    if vsnOpt.len > 0:
      result.add(quote do:
       var versionDflt = false
       `apId`.parNm = `vsnOpt`; `apId`.parSh = `vsnSh`; `apId`.parReq = 0
       `tabId`.add(argHelp(versionDflt, `apId`) & "write version to stdout"))
    let argStart = if mandatory.len > 0: "[required&optional-params]" else:
                                         "[optional-params]"
    var args = argStart &
               (if posIx != -1: " [" & $(fpars[posIx][0]) & "]" else: "")
    for i in 1 ..< len(fpars):
      let idef = fpars[i]
      let sdef = spars[i]
      result.add(newNimNode(nnkVarSection).add(sdef))     #Init vars
      if i != posIx:
        result.add(newNimNode(nnkVarSection).add(dpars[i]))
      callIt.add(newNimNode(nnkExprEqExpr).add(idef[0], sdef[0])) #Add to call
      if i != posIx:
        let parNm = $idef[0]
        let sh = toString(shOpt.getOrDefault(parNm))      #Add to perPar helpTab
        let defVal = sdef[0]
        let hlp=if parNm in helps: helps.getOrDefault(parNm) else: "set "&parNm
        let isReq = if i in mandatory: true else: false
        result.add(quote do:
         `apId`.parNm = `parNm`; `apId`.parSh = `sh`; `apId`.parReq = `isReq`
         `tabId`.add(argHelp(`defVal`, `apId`) & `hlp`))
        if isReq:
          result.add(quote do: `mandId`.add(`parNm`))
    result.add(quote do:                  # build one large help string
      let indentDoc = addPrefix(`prefixId`, `docId`)
      `apId`.help = `usageId` % [ "prelude", `prlude`, "doc", indentDoc,
                     "command", `cName`, "args", `args`, "options",
                     addPrefix(`prefixId` & "  ",
                               alignTable(`tabId`, 2*len(`prefixId`) + 2,
                                          `htColGap`, `htMinLst`, `htRowSep`,
                                          `htCols`)),
                     "sep", `subSepId` ]
      if `apId`.help[^1] != '\n':            # ensure newline @end of help
        `apId`.help &= "\n"
      if len(`prefixId`) > 0:             # to indent help in a multicmd context
        `apId`.help = addPrefix(`prefixId`, `apId`.help))

  proc defOptCases(): NimNode =
    result = newNimNode(nnkCaseStmt).add(quote do: optionNormalize(`pId`.key))
    result.add(newNimNode(nnkOfBranch).add(
      newStrLitNode("help"), toStrLitNode(shortHlp)).add(
        quote do:
          stdout.write(`apId`.help); raise newException(HelpOnly, "")))
    if vsnOpt.len > 0:
      if vsnOpt in shOpt:                     #There is also a short version tag
        result.add(newNimNode(nnkOfBranch).add(
          newStrLitNode(vsnOpt), newStrLitNode(vsnSh)).add(
            quote do:
              stdout.write(`vsnStr`,"\n"); raise newException(VersionOnly, "")))
      else:                                   #There is only a long version tag
        result.add(newNimNode(nnkOfBranch).add(newStrLitNode(vsnOpt)).add(
            quote do:
              stdout.write(`vsnStr`,"\n"); raise newException(VersionOnly, "")))
    for i in 1 ..< len(fpars):                # build per-param case clauses
      if i == posIx: continue                 # skip variable len positionals
      let parNm  = $fpars[i][0]
      let lopt   = optionNormalize(parNm)
      let spar   = spars[i][0]
      let dpar   = dpars[i][0]
      var maybeMandInForce = newNimNode(nnkEmpty)
      if `parNm` in `mandOvr`:
        maybeMandInForce = quote do:
          `mandInFId` = false
      let apCall = quote do:
        `apId`.key = `pId`.key
        `apId`.val = `pId`.val
        `apId`.sep = `pId`.sep
        `apId`.parNm = `parNm`
        `keyCountId`.inc(`parNm`)
        `apId`.parCount = `keyCountId`[`parNm`]
        if not argParse(`spar`, `dpar`, `apId`):
          raise newException(ParseError, "")
        discard delItem(`mandId`, `parNm`)
        `maybeMandInForce`
      if parNm in shOpt and lopt.len > 1:     # both a long and short option
        let parShOpt = $shOpt.getOrDefault(parNm)
        result.add(newNimNode(nnkOfBranch).add(
          newStrLitNode(lopt), newStrLitNode(parShOpt)).add(apCall))
      else:                                   # only a long option
        result.add(newNimNode(nnkOfBranch).add(newStrLitNode(lopt)).add(apCall))
    result.add(newNimNode(nnkElse).add(quote do:
      stderr.write("Bad option: \"" & `pId`.key & "\"\n" & `apId`.help)
      raise newException(ParseError, "")))

  proc defNonOpt(): NimNode =
    result = newStmtList()
    if posIx != -1:                           # code to parse non-option args
      result.add(newNimNode(nnkCaseStmt).add(quote do: postInc(`posNoId`)))
      let posId = spars[posIx][0]
      let tmpId = ident("tmp" & $posId)
      result[0].add(newNimNode(nnkElse).add(quote do:
        var rewind = false                  #Ugly machinery is so tmp=pos[0]..
        if len(`posId`) == 0:               #..type inference works.
          `posId`.setLen(1)
          rewind = true
        var `tmpId` = `posId`[0]
        `apId`.key = "positional $" & $`posNoId`
        `apId`.val = `pId`.key
        `apId`.sep = "="
        `apId`.parNm = `apId`.key
        `apId`.parCount = 1
        if not argParse(`tmpId`, `tmpId`, `apId`):
          raise newException(ParseError, "")
        if rewind: `posId`.setLen(0)
        `posId`.add(`tmpId`)))
    else:
      result.add(quote do:
        stderr.write(`proNm` & " does not expect non-option arguments.  Got\n" &
                     $`pId` & "\n" & `apId`.help)
        raise newException(ParseError, ""))

  let argPreP=argPre; let argPostP=argPost  #XXX ShouldBeUnnecessary
  proc callParser(): NimNode =
    result = quote do:
      if len(`argPreP`) > 0: parser(`argPreP`)    #Extra *compile-time* input
      parser()
      if len(`argPostP`) > 0: parser(`argPostP`)  #Extra *compile-time* input

  let iniVar=initVars(); let optCases=defOptCases(); let nonOpt=defNonOpt()
  let callPrs=callParser(); let retType=fpars[0]  #XXX ShouldBeUnnecessary
  result = quote do:
    from os               import commandLineParams
    from cligen/argcvt    import ArgcvtParams, argParse, argHelp
    from cligen/textUt    import addPrefix, TextTab, alignTable
    from cligen/parseopt3 import initOptParser, next, cmdEnd, cmdLongOption,
                                 cmdShortOption, optionNormalize
    import tables, strutils # import join, `%`
    proc `disNm`(`cmdLineId`: seq[string] = mergeParams(`cName`),
                 `docId`: string = `cmtDoc`, `usageId`: string = `usage`,
                 `prefixId`="", `subSepId`=""): `retType` =
      `iniVar`
      {.push hint[XDeclaredButNotUsed]: off.}
      proc parser(args=`cmdLineId`) =
        var `posNoId` = 0
        var `keyCountId` = initCountTable[string]()
        var `pId` = initOptParser(args, `apId`.shortNoVal, `apId`.longNoVal,
                                  `requireSeparator`, `sepChars`, `opChars`,
                                  `stopWords`)
        while true:
          next(`pId`)
          if `pId`.kind == cmdEnd: break
          case `pId`.kind
            of cmdLongOption, cmdShortOption:
              `optCases`
            else:
              `nonOpt`
      {.pop.}
      `callPrs`
      if `mandId`.len > 0 and `mandInFId`:
        stderr.write "Missing these required parameters:\n"
        for m in `mandId`: stderr.write "  ", m, "\n"
        stderr.write "Run command with --help for more details.\n"
        raise newException(ParseError, "")
      `callIt`
  when defined(printDispatch): echo repr(result)  # maybe print generated code

macro dispatch*(pro: typed, cmdName: string = "", doc: string = "",
                help: typed = { }, short: typed = { }, usage: string=dflUsage,
                prelude = "Usage:\n  ", echoResult: bool = false,
                requireSeparator: bool = false, sepChars = {'=', ':'},
                opChars={'+','-','*','/','%', '@',',', '.','&','^','~','|'},
                helpTabColumnGap = 2, helpTabMinLast = 16, helpTabRowSep = "",
                helpTabColumns = @[ helpTabOption, helpTabType, helpTabDefault,
                                    helpTabDescrip ],
                stopWords: seq[string] = @[], positional = "",
                argPre: seq[string] = @[], argPost: seq[string] = @[],
                suppress: seq[string] = @[], shortHelp = 'h',
                implicitDefault: seq[string] = @[], mandatoryHelp = "REQUIRED",
                mandatoryOverride: seq[string] = @[], delimit = ",",
                version: Version=("",""), noAutoEcho: bool=false): untyped =
  ## A convenience wrapper to both generate a command-line dispatcher and then
  ## call the dispatcher & exit; Usage is the same as the dispatchGen() macro.
  result = newStmtList()
  result.add(newCall(
    "dispatchGen", pro, cmdName, doc, help, short, usage, prelude, echoResult,
      requireSeparator, sepChars, opChars, helpTabColumnGap, helpTabMinLast,
      helpTabRowSep, helpTabColumns, stopWords, positional, argPre, argPost,
      suppress, shortHelp, implicitDefault, mandatoryHelp, mandatoryOverride,
      delimit, version))
  let disNm = ident("dispatch" & $pro)
  let autoEc = not noAutoEcho.boolVal
  if formalParams(pro.symbol.getImpl)[0].kind == nnkEmpty:
    result.add(quote do:                      #No Return Type At All
      try: `disNm`(); quit(0)
      except HelpOnly, VersionOnly: quit(0)
      except ParseError: quit(1))
  elif echoResult.boolVal:
    result.add(quote do:                      #CLI author requests echo
      try: echo `disNm`(); quit(0)
      except HelpOnly, VersionOnly: quit(0)
      except ParseError: quit(1))
  else:
    result.add(quote do:
      when compiles(int(`disNm`())):          #Can convert to int
        try: quit(int(`disNm`()))
        except HelpOnly, VersionOnly: quit(0)
        except ParseError: quit(1)
      elif bool(`autoEc`) and compiles(echo `disNm`()): #autoEc mode && have `$`
        try: echo `disNm`(); quit(0)
        except HelpOnly, VersionOnly: quit(0)
        except ParseError: quit(1)
      else:                                   #unconvertible; Just ignore
        try: discard `disNm`(); quit(0)
        except HelpOnly, VersionOnly: quit(0)
        except ParseError: quit(1))

proc subCmdName(node: NimNode): string {.compileTime.} =
  ## Get last cmdName= argument, if any, in bracket expression, or name of 1st
  ## element of bracket if none given.
  result = $node[0]
  for child in node:
    if child.kind == nnkExprEqExpr:
      if eqIdent(child[0], "cmdName"):
        result = $child[1]

proc subCmdEchoRes(node: NimNode): bool {.compileTime.} =
  ##Get last echoResult value, if any, in bracket expression
  result = false
  for child in node:
    if child.kind == nnkExprEqExpr:
      if eqIdent(child[0], "echoResult"): return true

proc subCmdNoAutoEc(node: NimNode): bool {.compileTime.} =
  ##Get last noAutoEcho value, if any, in bracket expression
  result = false
  for child in node:
    if child.kind == nnkExprEqExpr:
      if eqIdent(child[0], "noAutoEcho"): return true

var cligenVersion* = ""

macro dispatchMulti*(procBrackets: varargs[untyped]): untyped =
  ## A convenience wrapper to both generate a multi-command dispatcher and then
  ## call the dispatcher & quit; procBrackets=arg lists for dispatchGen(), e.g,
  ## dispatchMulti([ foo, short={"dryRun": "n"} ], [ bar, doc="Um" ]).
  result = newStmtList()
  for p in procBrackets:
    var c = newCall("dispatchGen")
    copyChildrenTo(p, c)
    c.add(newParam("prelude", newStrLitNode("")))
    result.add(c)
  let fileParen = lineinfo(procBrackets)  # Infer multi-cmd name from lineinfo
  let Slash = if rfind(fileParen, "/") < 0: 0 else: rfind(fileParen, "/") + 1
  let Paren = rfind(fileParen, ".nim(") - 1
  let srcBase = newStrLitNode(if Paren < 0: "??" else: fileParen[Slash..Paren])
  let arg0Id = ident("arg0")
  let restId = ident("rest")
  let dashHelpId = ident("dashHelp")
  let multiId = ident("multi")
  let subCmdsId = ident("subCmds")
  var multiDef = newStmtList()
  multiDef.add(quote do:
    import os
    proc `multiId`(subCmd: seq[string]) =
      let n = subCmd.len
      let `arg0Id` = if n > 0: subCmd[0] else: "help"
      let `restId`: seq[string] = if n > 1: subCmd[1..<n] else: @[ ])
  var cases = multiDef[0][1][^1].add(newNimNode(nnkCaseStmt).add(arg0Id))
  var helps = (quote do:
        echo ("Usage:  This is a multiple-dispatch cmd.  Usage is like\n" &
              "  $1 subcommand [subcommand-opts & args]\n" &
              "where subcommand syntaxes are as follows:\n") % [ `srcBase` ]
        let `dashHelpId` = @[ "--help" ])
  var cnt = 0
  for p in procBrackets:
    inc(cnt)
    let qnm = $srcBase & "_" & $p[0]            #qualified name
    let disNm = ident("dispatch" & $p[0])
    let sCmdNm = newStrLitNode(subCmdName(p))
    let sCmdEcR = subCmdEchoRes(p)
    let sCmdAuEc = not subCmdNoAutoEc(p)
    if sCmdEcR:
      cases[^1].add(newNimNode(nnkOfBranch).add(sCmdNm).add(quote do:
        try: echo `disNm`(mergeParams(`qnm`, `restId`)); quit(0)
        except HelpOnly, VersionOnly: quit(0)
        except ParseError: quit(1)))
    else:
      cases[^1].add(newNimNode(nnkOfBranch).add(sCmdNm).add(quote do:
        when compiles(int(`disNm`())):          #Can convert to int
          try: quit(int(`disNm`(mergeParams(`qnm`, `restId`))))
          except HelpOnly, VersionOnly: quit(0)
          except ParseError: quit(1)
        elif bool(`sCmdAuEc`) and compiles(echo `disNm`()):  #autoEc && have `$`
          try: echo `disNm`(mergeParams(`qnm`, `restId`)); quit(0)
          except HelpOnly, VersionOnly: quit(0)
          except ParseError: quit(1)
        elif compiles(type(`disNm`())):         #there is a type to discard
          try: discard `disNm`(mergeParams(`qnm`, `restId`)); quit(0)
          except HelpOnly, VersionOnly: quit(0)
          except ParseError: quit(1)
        else:                                   #void return
          try: `disNm`(mergeParams(`qnm`, `restId`)); quit(0)
          except HelpOnly, VersionOnly: quit(0)
          except ParseError: quit(1)))
    let sep = if cnt < len(procBrackets): "\n" else: ""
    helps.add(quote do:
      when compiles(type(`disNm`())):
        try: discard `disNm`(`dashHelpId`, prefix="  ", subSep=`sep`)
        except HelpOnly: discard
      else:
        try: `disNm`(`dashHelpId`, prefix="  ", subSep=`sep`)
        except HelpOnly: discard)
  cases[^1].add(newNimNode(nnkElse).add(helps))
  result.add(multiDef)
  result.add(quote do:
    var `subCmdsId`: seq[string] = @[ ])
  for p in procBrackets:
    result.add(newCall("add", subCmdsId, newStrLitNode(subCmdName(p))))
  let vsnTree = newTree(nnkTupleConstr, newStrLitNode("version"),
                                        newIdentNode("cligenVersion"))
  result.add(newCall("dispatch", multiId, newParam("stopWords", subCmdsId),
                     newParam("version", vsnTree),
                     newParam("cmdName", srcBase), newParam("usage", quote do:
    "${prelude}$command {subcommand}\n" &
     "where {subcommand} is one of:\n  " & join(`subCmdsId`, " ") & "\n" &
     "Run top-level cmd with subcmd \"help\" or no subcmd to get all helps.\n" &
     "Run a subcommand with --help to see only help for that." &
     (if cligenVersion.len>0:"\nTop-level --version also available"else:""))))
  when defined(printMultiDisp): echo repr(result)  # maybe print generated code

proc mergeParams*(qualifiedName="", cmdLine=commandLineParams()): seq[string] =
  ##This is a dummy parameter merge to provide a hook for CLI authors to create
  ##the `seq[string]` to be parsed from whatever run-time sources (likely based
  ##on `qualifiedName`) that they would like. Here we just pass through cmdLine.
  ##In a single `dispatch` context, `qualifiedName` simply is `cmdName` while in
  ##a `dispatchMulti` context it is `"<mainCommand>_<subCommand>"`.
  cmdLine
