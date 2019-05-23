import os, macros, tables, cligen/[parseopt3, argcvt, textUt, sysUt, macUt],
       strutils, critbits
export commandLineParams, lengthen, initOptParser, next, optionNormalize,
       ArgcvtParams, argParse, argHelp, getDescription, join, `%`, CritBitTree,
       incl, valsWithPfx, contains, addPrefix, wrap, TextTab, alignTable,
       suggestions, split, helpCase, postInc, delItem

const clUse* = "$command $args\n$doc  Options(opt-arg sep :|=|spc):\n$options"
const clUsage* = "Usage:\n  " & clUse   #Use is for dispatchMulti else Usage

type    # Main defns CLI authors need be aware of (besides top-level API calls)
  ClHelpCol* = enum clOptKeys, clValType, clDflVal, clDescrip

  ClCfg* = object  ## Settings tending to be program- or CLI-author-global
    version*:     string
    hTabCols*:    seq[ClHelpCol] ## selects columns to format
    hTabRowSep*:  string         ## separates rows, e.g. "\n" double spaces
    hTabColGap*:  int            ## number of spaces to separate cols by
    hTabMinLast*: int            ## narrowest rightmost col no matter term width
    hTabVal4req*: string         ## ``"REQUIRED"`` (or ``"NEEDED"``, etc.).
    reqSep*:      bool           ## ``parseopt3.initOptParser`` parameter
    sepChars*:    set[char]      ## ``parseopt3.initOptParser`` parameter
    opChars*:     set[char]      ## ``parseopt3.initOptParser`` parameter

  HelpOnly*    = object of Exception
  VersionOnly* = object of Exception
  ParseError*  = object of Exception

{.push hint[GlobalVar]: off.}
var clCfg* = ClCfg(
  version:     "",
  hTabCols:    @[ clOptKeys, clValType, clDflVal, clDescrip ],
  hTabRowSep:  "",
  hTabColGap:  2,
  hTabMinLast: 16,
  hTabVal4req: "REQUIRED",
  reqSep:      false,
  sepChars:    { '=', ':' },
  opChars:     { '+', '-', '*', '/', '%', '@', ',', '.', '&',
                 '|', '~', '^', '$', '#', '<', '>', '?'})
{.pop.}

proc toInts*(x: seq[ClHelpCol]): seq[int] =
  ##Internal routine to convert help column enums to just ints for `alignTable`.
  for e in x: result.add(int(e))

type    #Utility types/code for generated parser/dispatchers for parseOnly mode
  ClStatus* = enum clBadKey,                        ## Unknown long key
                   clBadVal,                        ## Unparsable value
                   clNonOption,                     ## Unexpected non-option
                   clMissing,                       ## Mandatory but missing
                   clParseOptErr,                   ## parseopt error
                   clOk,                            ## Option parse part ok
                   clPositional,                    ## Expected non-option
                   clHelpOnly, clVersionOnly        ## Early Exit requests

  ClParse* = tuple[paramName: string,   ## Param name/long opt key
                   unparsedVal: string, ## Unparsed val ("" for missing)
                   message: string,     ## default error message
                   status: ClStatus]    ## Parse status for param
const ClErrors* = { clBadKey, clBadVal, clNonOption, clMissing }
const ClExit*   = { clHelpOnly, clVersionOnly }
const ClNoCall* = ClErrors + ClExit

proc contains*(x: openArray[ClParse], paramName: string): bool =
  ##Test if the ``seq`` updated via ``setByParse`` contains a parameter.
  for e in x:
    if e.paramName == paramName: return true

proc contains*(x: openArray[ClParse], status: ClStatus): bool =
  ##Test if the ``seq`` updated via ``setByParse`` contains a certain status.
  for e in x:
    if e.status == status: return true

proc numOfStatus*(x: openArray[ClParse], stati: set[ClStatus]): int =
  ##Count elements in the ``setByParse seq`` with parse status in ``stati``.
  for e in x:
    if e.status in stati: inc(result)

proc next*(x: openArray[ClParse], stati: set[ClStatus], start=0): int =
  ##First index after startIx in ``setByParse seq`` w/parse status in ``stati``.
  result = -1
  for i, e in x:
    if e.status in stati: return i

#[ Define many things used to interpolate into Overall Structure below ]#
proc dispatchId(name: string="", cmd: string="", rep: string=""): NimNode =
  result = if name.len > 0: ident(name)   #Nim ident for gen'd parser-dispatcher
           elif cmd.len > 0: ident("dispatch" & cmd)  #XXX illegal chars?
           else: ident("dispatch" & rep)

proc containsParam(fpars: NimNode, key: string): bool =
  let k = key.optionNormalize
  for declIx in 1 ..< len(fpars):           #default for result = false
    let idefs = fpars[declIx]               #Must use similar logic to..
    for i in 0 ..< len(idefs) - 3:          #..formalParamExpand because
      if optionNormalize($idefs[i]) == k: return true        #..`suppress` is itself one of
    if optionNormalize($idefs[^3]) == k: return true         #..the symbol lists we check.

proc formalParamExpand*(fpars: NimNode, n: auto,
                        suppress: seq[string]= @[]): NimNode =
  ## a,b,..,c:type [maybe=val] --> a:type, b:type, ..., c:type [maybe=val]
  result = newNimNode(nnkFormalParams)
  result.add(fpars[0])                                  # just copy ret value
  for p in suppress:
    if not fpars.containsParam(p):
      error repr(n[0]) & " has no param matching `suppress` key \"" & p & "\""
  for declIx in 1 ..< len(fpars):
    let idefs = fpars[declIx]
    for i in 0 ..< len(idefs) - 3:
      if $idefs[i] notin suppress:
        result.add(newIdentDefs(idefs[i], idefs[^2]))
    if $idefs[^3] notin suppress:
      result.add(newIdentDefs(idefs[^3], idefs[^2], idefs[^1]))

proc formalParams*(n: NimNode, suppress: seq[string]= @[]): NimNode =
  ## Extract expanded formal parameter list from the return value of .getImpl
  for kid in n:
    if kid.kind == nnkFormalParams:
      return formalParamExpand(kid, n, suppress)
  error "formalParams requires a proc argument."
  return nil                #not-reached

proc parseHelps(helps: NimNode, proNm: auto, fpars: auto): Table[string,(string,string)]=
  result = initTable[string, (string, string)]() #help key & text for any param
  for ph in helps:
    let p: string = (ph[1][0]).strVal
    let k: string = (ph[1][0]).strVal.optionNormalize
    let h: string = (ph[1][1]).strVal
    result[k] = (p, h)
    if not fpars.containsParam(k):
      error $proNm & " has no param matching `help` key \"" & p & "\""

proc parseShorts(shorts: NimNode, proNm: auto, fpars: auto): Table[string,char]=
  result = initTable[string, char]()  #table giving user-specified short options
  for losh in shorts:
    let lo: string = (losh[1][0]).strVal.optionNormalize
    let sh: char = char((losh[1][1]).intVal)
    result[lo] = sh
    if lo.len > 0 and not fpars.containsParam(lo) and
         lo != "version" and lo != "help" and lo != "helpsyntax":
      error $proNm & " has no param matching `short` key \"" & lo & "\""

proc dupBlock(fpars: NimNode, posIx: int, userSpec: Table[string, char]):
     Table[string, char] =      # Table giving short[param] avoiding collisions
  result = initTable[string, char]()         # short option for param
  var used: set[char] = {}                   # used shorts; bit vector ok
  if "help" notin userSpec:
    result["help"] = 'h'
    used.incl('h')
  if "" in userSpec: return                  # Empty string key==>no short opts
  for lo, sh in userSpec:
    result[lo] = sh
    used.incl(sh)
  for i in 1 ..< len(fpars):                 # [0] is proc, not desired here
    if i == posIx: continue                  # positionals get no option char
    let parNm = optionNormalize($fpars[i][0])
    if parNm.len == 1 and parNm[0] == result["help"]:
      error "`"&parNm&"` collides with `short[\"help\"]`.  Change help short."
    let sh = parNm[0]                        # abbreviation is 1st character
    if sh notin used and parNm notin result: # still available
      result[parNm] = sh
      used.incl(sh)
  let tmp = result        #One might just put sh != '\0' above, but this lets
  for k, v in tmp:        #CLI authors also block -h via short={"help": '\0'}.
    if v == '\0': result.del(k)

const AUTO = "\0"             #Just some "impossible-ish" identifier

proc posIxGet(positional: string, fpars: NimNode): int =
  # Find the proc param to map to optional positional arguments of a command.
  if positional == "":
    return -1
  if positional != AUTO:
    result = findByName(positional, fpars)
    if result == -1:
      error("requested positional argument catcher " & positional &
            " is not in formal parameter list")
    return
  result = -1                     # No optional positional arg param yet found
  for i in 1 ..< len(fpars):
    let idef = fpars[i]           # 1st typed,non-defaulted seq; Allow override?
    if idef[1].kind != nnkEmpty and idef[2].kind == nnkEmpty and
       typeKind(getType(idef[1])) == ntySequence:
      if result != -1:            # Allow multiple seq[T]s via "--" separators?
        warning("cligen only supports one seq param for positional args; using"&
                " `" & $fpars[result][0] & "`, not `" & $fpars[i][0] & "`.  " &
                "Use `positional` parameter to `dispatch` to override this.")
      else:
        result = i

include cligen/syntaxHelp

macro dispatchGen*(pro: typed{nkSym}, cmdName: string="", doc: string="",
  help: typed={}, short: typed={}, usage: string=clUsage, cf: ClCfg=clCfg,
  echoResult=false, noAutoEcho=false, positional: static string=AUTO,
  suppress: seq[string] = @[], implicitDefault: seq[string] = @[],
  mandatoryOverride: seq[string] = @[], stopWords: seq[string] = @[],
  dispatchName="", mergeNames: seq[string] = @[], docs: ptr var seq[string]=nil,
  setByParse: ptr var seq[ClParse]=nil): untyped =
  ##Generate command-line dispatcher for proc ``pro`` named ``dispatchName``
  ##(defaulting to ``dispatchPro``) with generated help/syntax guided by
  ##``cmdName``, ``doc``, and ``cf``.  Parameters with no explicit default in
  ##the proc become mandatory command arguments while those with default values
  ##become command options. Each proc parameter type needs in-scope ``argParse``
  ##& ``argHelp`` procs.  ``cligen/argcvt`` defines them for basic types & basic
  ##collections (``int``, ``string``, ``enum``, .., ``seq[T], set[T], ..``).
  ##
  ##``help`` is a ``{(paramNm, str)}`` of per-param help, eg. ``{"quiet": "be
  ##quiet"}``.  Often, only these help strings are needed for a decent CLI.
  ##
  ##``short`` is a ``{(paramNm, char)}`` of per-param single-char option keys.
  ##
  ##``usage`` is a help template interpolating $command $args $doc $options.
  ##
  ##``cf`` controls whole program aspects of generated CLIs. See ``ClCfg`` docs.
  ##
  ##Default exit protocol is: quit(int(result)) or (echo $result or discard;
  ##quit(0)) depending on what compiles.  True ``echoResult`` forces echo while
  ##``noAutoEcho`` blocks it (=>int()||discard).  Technically, ``cligenQuit``
  ##implements this behavior.
  ##
  ##By default, ``cligen`` maps the first non-defaulted ``seq[]`` proc parameter
  ##to any non-option/positional command args.  ``positional`` selects another.
  ##Set ``positional`` to the empty string (``""``) to disable this entirely.
  ##
  ##``suppress`` is a list of formal parameter names to exclude from the parse-
  ##assign system.  Such names are effectively pinned to their default values.
  ##
  ##``implicitDefault`` is a list of formal parameter names allowed to default
  ##to the Nim default value for a type, rather than becoming mandatory, when
  ##they lack an explicit initializer.
  ##
  ##``mandatoryOverride`` is a list of formal parameter names which, if set by a
  ##CLI user, override the erroring out if any mandatory settings are missing.
  ##
  ##``stopWords`` is a ``seq[string]`` of words beyond which ``-.*`` no longer
  ##signifies an option (like the common sole ``--`` command argument).
  ##
  ##``mergeNames`` gives the ``cmdNames`` param passed to ``mergeParams``, which
  ##defaults to ``@[cmdName]`` if ``mergeNames`` is ``@[]``.
  ##
  ##``docs`` is ``addr(some var seq[string])`` to which to append each main doc
  ##comment or its replacement doc=text.  Default of ``nil`` means do nothing.
  ##
  ##``setByParse`` is ``addr(some var seq[ClParse])``.  When non-nil, this var
  ##collects each parameter seen, keyed under its long/param name (i.e., parsed
  ##but not converted to native types).  Wrapped procs can inspect this or even
  ##convert args themselves to revive ``parseopt``-like iterative interpreting.
  ##``cligen`` provides convenience procs to use ``setByParse``: ``contains``,
  ##``numOfStatus`` & ``next``. Note that ordinary Nim procs, from inside calls,
  ##do not know how params got their values (positional, keyword, defaulting).
  ##Wrapped procs accessing ``setByParse`` are inherently command-line only. So,
  ##this ``var seq`` needing to be declared before such procs for such access is
  ##ok.  Ideally, keep important functionality Nim-callable.  ``setByParse`` may
  ##also be useful combined with the ``parseOnly`` arg of generated dispatchers.
  let impl = pro.getImpl
  if impl == nil: error "getImpl(" & $pro & ") returned nil."
  let fpars = formalParams(impl, toStrSeq(suppress))
  var cmtDoc: string = $doc
  if cmtDoc.len == 0:                   # allow caller to override commentDoc
    collectComments(cmtDoc, impl)
    cmtDoc = strip(cmtDoc)
  let cf = cf #sub-scope quote-do's cannot access macro args w/o shadow locals.
  let setByParse = setByParse
  let proNm = $pro                      # Name of wrapped proc
  let cName = if len($cmdName) == 0: proNm else: $cmdName
  let disNm = dispatchId($dispatchName, cName, proNm) # Name of dispatch wrapper
  let helps = parseHelps(help, proNm, fpars)
  let posIx = posIxGet(positional, fpars) #param slot for positional cmd args|-1
  let shOpt = dupBlock(fpars, posIx, parseShorts(short, proNm, fpars))
  let shortH = shOpt["help"]
  var spars = copyNimTree(fpars)        # Create shadow/safe suffixed params.
  var dpars = copyNimTree(fpars)        # Create default suffixed params.
  var mandatory = newSeq[int]()         # At the same time, build metadata on..
  let implDef = toStrSeq(implicitDefault)
  for p in implDef:
    if not fpars.containsParam(p):
      error $proNm&" has no param matching `implicitDefault` key \"" & p & "\""
  let mandOvr = toStrSeq(mandatoryOverride)
  for p in mandOvr:
   if not fpars.containsParam(p):
     error $proNm&" has no param matching `mandatoryOverride` key \"" & p & "\""
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
  let usageId = ident("usage")          # gen proc parameter
  let cmdLineId = ident("cmdline")      # gen proc parameter
  let vsnSh = if "version" in shOpt: $shOpt["version"] else: "\0"
  let prefixId = ident("prefix")        # local help prefix param
  let pId = ident("p")                  # local OptParser result handle
  let allId = ident("allParams")        # local list of all parameters
  let cbId = ident("crbt")              # CritBitTree for prefix lengthening
  let mandId = ident("mand")            # local list of mandatory parameters
  let mandInFId = ident("mandInForce")  # mandatory-in-force flag
  let apId = ident("ap")                # ArgcvtParams
  var callIt = newNimNode(nnkCall)      # call of wrapped proc in genproc
  callIt.add(pro)
  let shortHlp = newStrLitNode($shortH)
  let setByParseId = ident("setByP")    # parse recording var seq

  proc initVars(): NimNode =            # init vars & build help str
    result = newStmtList()
    let tabId = ident("tab")            # local help table var
    result.add(quote do:
      var `apId`: ArgcvtParams
      `apId`.val4req = `cf`.hTabVal4req
      let shortH = `shortHlp`
      var `allId`: seq[string] = @[ "help", "help-syntax" ]
      var `cbId`: CritBitTree[string]
      `cbId`.incl(optionNormalize("help"), "help")
      `cbId`.incl(optionNormalize("help-syntax"), "help-syntax")
      var `mandId`: seq[string]
      var `mandInFId` = true
      var `tabId`: TextTab =
        @[ @[ "-"&shortH&", --help", "", "", "print this cligen-erated help" ],
           @[ "--help-syntax", "", "", "advanced: prepend,plurals,.." ] ]
      `apId`.shortNoVal = { shortH[0] }               # argHelp(bool) updates
      `apId`.longNoVal = @[ "help", "help-syntax" ]   # argHelp(bool) appends
      let `setByParseId`: ptr seq[ClParse] = `setByParse`)
    result.add(quote do:
      if `cf`.version.len > 0:
        `apId`.parNm = "version"; `apId`.parSh = `vsnSh`
        `apId`.parReq = 0; `apId`.parRend = `apId`.parNm
        `tabId`.add(argHelp(false, `apId`) & "print version"))
    let argStart = if mandatory.len > 0: "[required&optional-params]" else:
                                         "[optional-params]"
    let posHelp = if posIx != -1:
                    if $fpars[posIx][0] in helps:
                      helps[optionNormalize($fpars[posIx][0])][1]
                    else:
                      let typeName = fpars[posIx][1][1].strVal
                      "[" & $(fpars[posIx][0]) & ": " & typeName & "...]"
                  else: ""
    var args = argStart & " " & posHelp
    for i in 1 ..< len(fpars):
      let idef = fpars[i]
      let sdef = spars[i]
      result.add(newNimNode(nnkVarSection).add(sdef))     #Init vars
      if i != posIx:
        result.add(newVarStmt(dpars[i][0], sdef[0]))
      callIt.add(newNimNode(nnkExprEqExpr).add(idef[0], sdef[0])) #Add to call
      if i != posIx:
        let parNm = $idef[0]
        let defVal = sdef[0]
        let pNm = parNm.optionNormalize
        let sh = $shOpt.getOrDefault(pNm)       #Add to perPar helpTab
        let hky = helps.getOrDefault(pNm)[0]
        let hlp = helps.getOrDefault(pNm)[1]
        let isReq = if i in mandatory: true else: false
        result.add(quote do:
         `apId`.parNm = `parNm`; `apId`.parSh = `sh`; `apId`.parReq = `isReq`
         `apId`.parRend = if `hky`.len>0: `hky` else:helpCase(`parNm`,clLongOpt)
         let descr = getDescription(`defVal`, `parNm`, `hlp`)
         `tabId`.add(argHelp(`defVal`, `apId`) & descr)
         if `apId`.parReq != 0: `tabId`[^1][2] = `apId`.val4req
         `cbId`.incl(optionNormalize(`parNm`), `apId`.parRend)
         `allId`.add(helpCase(`parNm`, clLongOpt)))
        if isReq:
          result.add(quote do: `mandId`.add(`parNm`))
    result.add(quote do:                  # build one large help string
      let indentDoc = addPrefix(`prefixId`, wrap(`prefixId`, `cmtDoc`))
      `apId`.help = `usageId` % [ "doc",indentDoc, "command",`cName`,
                                  "args",`args`, "options",
                  addPrefix(`prefixId` & "  ",
                            alignTable(`tabId`, 2*len(`prefixId`) + 2,
                                       `cf`.hTabColGap, `cf`.hTabMinLast,
                                       `cf`.hTabRowSep, toInts(`cf`.hTabCols)))]
      if `apId`.help.len > 0 and `apId`.help[^1] != '\n':   #ensure newline @end
        `apId`.help &= "\n"
      if len(`prefixId`) > 0:             # to indent help in a multicmd context
        `apId`.help = addPrefix(`prefixId`, `apId`.help))

  proc defOptCases(): NimNode =
    result = newNimNode(nnkCaseStmt).add(quote do:
      if p.kind == cmdLongOption: lengthen(`cbId`, `pId`.key) else: `pId`.key)
    result.add(newNimNode(nnkOfBranch).add(
      newStrLitNode("help"), shortHlp).add(
        quote do:
          if cast[pointer](`setByParseId`) != nil:
            `setByParseId`[].add(("help", "", `apId`.help, clHelpOnly))
            return                            #Do not try to keep parsing
          else:
            stdout.write(`apId`.help); raise newException(HelpOnly, "")))
    result.add(newNimNode(nnkOfBranch).add(
      newStrLitNode("helpsyntax")).add(
        quote do:
          if cast[pointer](`setByParseId`) != nil:
            `setByParseId`[].add(("helpsyntax", "", syntaxHelp, clHelpOnly))
            return                            #Do not try to keep parsing
          else:
            stdout.write(syntaxHelp); raise newException(HelpOnly, "")))
    result.add(newNimNode(nnkOfBranch).add(
      newStrLitNode("version"), newStrLitNode(vsnSh)).add(
        quote do:
          if cast[pointer](`setByParseId`) != nil:
            `setByParseId`[].add(("version", "", `cf`.version, clVersionOnly))
            return                        #Do not try to keep parsing
          else:
            stdout.write(`cf`.version,"\n");raise newException(VersionOnly,"")))
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
        `apId`.parRend = helpCase(`parNm`, clLongOpt)
        `keyCountId`.inc(`parNm`)
        `apId`.parCount = `keyCountId`[`parNm`]
        if cast[pointer](`setByParseId`) != nil:
          if argParse(`spar`, `dpar`, `apId`):
            `setByParseId`[].add((`parNm`,`pId`.val, "", clOk))
          else:
            `setByParseId`[].add((`parNm`,`pId`.val,
                                 "Cannot parse arg to " & `apId`.key, clBadVal))
        else:
          if not argParse(`spar`, `dpar`, `apId`):
            stderr.write `apId`.msg
            raise newException(ParseError, "Cannot parse arg to " & `apId`.key)
        discard delItem(`mandId`, `parNm`)
        `maybeMandInForce`
      if lopt in shOpt and lopt.len > 1:      # both a long and short option
        let parShOpt = $shOpt.getOrDefault(lopt)
        result.add(newNimNode(nnkOfBranch).add(
          newStrLitNode(lopt), newStrLitNode(parShOpt)).add(apCall))
      else:                                   # only a long option
        result.add(newNimNode(nnkOfBranch).add(newStrLitNode(lopt)).add(apCall))
    let ambigReport = quote do:
      let ks = `cbId`.valsWithPfx(p.key)
      let msg=("Ambiguous long option prefix \"$1\" matches:\n  $2 "%[`pId`.key,
              ks.join("\n  ")]) & "\nRun with --help for more details.\n"
      if cast[pointer](`setByParseId`) != nil:
        `setByParseId`[].add((`piD`.key, `pId`.val, msg, clBadKey))
      else:
        stderr.write(msg)
        raise newException(ParseError, "Unknown option")
    result.add(newNimNode(nnkOfBranch).add(newStrLitNode("")).add(ambigReport))
    result.add(newNimNode(nnkElse).add(quote do:
      var mb, k: string
      k = "short"
      if `pId`.kind == cmdLongOption:
        k = "long"
        var idNorm: seq[string]
        for id in allParams: idNorm.add(optionNormalize(id))
        let sugg = suggestions(optionNormalize(`pId`.key), idNorm, allParams)
        if sugg.len > 0:
          mb &= "Maybe you meant one of:\n\t" & join(sugg, " ") & "\n\n"
      let msg = ("Unknown " & k & " option: \"" & `pId`.key & "\"\n\n" &
                 mb & "Run with --help for full usage.\n")
      if cast[pointer](`setByParseId`) != nil:
        `setByParseId`[].add((`piD`.key, `pId`.val, msg, clBadKey))
      else:
        stderr.write(msg)
        raise newException(ParseError, "Unknown option")))

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
        `apId`.parRend = helpCase(`apId`.key, clLongOpt)
        `apId`.parCount = 1
        let msg = "Cannot parse " & `apId`.key
        if cast[pointer](`setByParseId`) != nil:
          if argParse(`tmpId`,`tmpId`,`apId`):
            `setByParseId`[].add((`apId`.key, `apId`.val, "", clPositional))
          else:
            `setByParseId`[].add((`apId`.key, `apId`.val, msg, clBadVal))
        else:
          if not argParse(`tmpId`, `tmpId`, `apId`):
            stderr.write `apId`.msg
            raise newException(ParseError, msg)
        if rewind: `posId`.setLen(0)
        `posId`.add(`tmpId`)))
    else:
      result.add(quote do:
        let msg = "Unexpected non-option " & $`pId`
        if cast[pointer](`setByParseId`) != nil:
          `setByParseId`[].add((`apId`.key, `pId`.val, msg, clNonOption))
        else:
          stderr.write(`cName`&" does not expect non-option arguments.  Got\n" &
                       $`pId` & "\nRun with --help for full usage.\n")
          raise newException(ParseError, msg))

  let iniVar=initVars(); let optCases=defOptCases(); let nonOpt=defNonOpt()
  let retType=fpars[0]
  let mrgNames = if mergeNames[1].len == 0:   #@[] => Prefix[OpenSym,Bracket]
                   quote do: @[ `cName` ]
                 else: mergeNames
  let docsVar = if   docs.kind == nnkAddr: docs[0]
                elif docs.kind == nnkCall: docs[1]
                else: newNimNode(nnkEmpty)
  let docsStmt = if docs.kind == nnkAddr or docs.kind == nnkCall:
                   quote do: `docsVar`.add(`cmtDoc`)
                 else: newNimNode(nnkEmpty)
  result = quote do:                                    #Overall Structure
    if cast[pointer](`docs`) != nil: `docsStmt`
    proc `disNm`(`cmdLineId`: seq[string] = mergeParams(`mrgNames`),
                 `usageId`=`usage`, `prefixId`="", parseOnly=false): `retType` =
      {.push hint[XDeclaredButNotUsed]: off.}
      `iniVar`
      proc parser(args=`cmdLineId`) =
        var `posNoId` = 0
        var `keyCountId` = initCountTable[string]()
        var `pId` = initOptParser(args, `apId`.shortNoVal, `apId`.longNoVal,
                                  `cf`.reqSep, `cf`.sepChars, `cf`.opChars,
                                  `stopWords`)
        while true:
          next(`pId`)
          if `pId`.kind == cmdEnd: break
          if `pId`.kind == cmdError:
            if cast[pointer](`setByParseId`) != nil:
              `setByParseId`[].add(("", "", `pId`.message, clParseOptErr))
            if not parseOnly:
              stderr.write(`pId`.message, "\n")
            break
          case `pId`.kind
            of cmdLongOption, cmdShortOption:
              `optCases`
            else:
              `nonOpt`
      {.pop.}
      parser()
      if `mandId`.len > 0 and `mandInFId`:
        if cast[pointer](`setByParseId`) != nil:
          for m in `mandId`:
            `setByParseId`[].add((m, "", "Missing " & m, clMissing))
        else:
          stderr.write "Missing these required parameters:\n"
          for m in `mandId`: stderr.write "  ", m, "\n"
          stderr.write "Run command with --help for more details.\n"
          raise newException(ParseError, "Missing one/some mandatory args")
      if parseOnly or (cast[pointer](`setByParseId`) != nil and
          `setByParseId`[].numOfStatus(ClNoCall) > 0):
        return
      `callIt`
  when defined(printDispatch): echo repr(result)  # maybe print generated code

template cligenQuit*(p: untyped, echoResult=false, noAutoEcho=false): auto =
  when echoResult:                            #CLI author requests echo
    try: echo p; quit(0)                      #May compile-time fail, but do..
    except HelpOnly, VersionOnly: quit(0)     #..want bubble up to CLI auth.
    except ParseError: quit(1)
  elif compiles(int(p)):                      #Can convert to int
    try: quit(int(p))
    except HelpOnly, VersionOnly: quit(0)
    except ParseError: quit(1)
  elif not noAutoEcho and compiles(echo p):   #autoEcho && have `$`
    try: echo p; quit(0)
    except HelpOnly, VersionOnly: quit(0)
    except ParseError: quit(1)
  elif compiles(type(p)):                     #no convert to int,str but typed
    try: discard p; quit(0)
    except HelpOnly, VersionOnly: quit(0)
    except ParseError: quit(1)
  else:                                       #void return type
    try: p; quit(0)
    except HelpOnly, VersionOnly: quit(0)
    except ParseError: quit(1)

template cligenHelp*(p:untyped, hlp: untyped, use: untyped, pfx: untyped): auto=
  when compiles(type(p())):
    try: discard p(hlp, usage=use, prefix=pfx)
    except HelpOnly: discard
  else:
    try: p(hlp, usage=use, prefix=pfx)
    except HelpOnly: discard

macro cligenQuitAux*(cmdLine:seq[string], dispatchName: string, cmdName: string,
                     pro: untyped, echoResult: bool, noAutoEcho: bool,
                     mergeNames: seq[string] = @[]): untyped =
  let disNm = dispatchId($dispatchName, $cmdName, repr(pro))
  let mergeNms = toStrSeq(mergeNames) & cmdName.strVal
  quote do: cligenQuit(`disNm`(mergeParams(`mergeNms`, `cmdLine`)),
                       `echoResult`, `noAutoEcho`)

template dispatch*(pro: typed{nkSym}, cmdName="", doc="", help: typed={},
 short:typed={},usage=clUsage, cf:ClCfg=clCfg,echoResult=false,noAutoEcho=false,
 positional=AUTO, suppress:seq[string] = @[], implicitDefault:seq[string] = @[],
 mandatoryOverride: seq[string] = @[], dispatchName="",
 mergeNames: seq[string] = @[], stopWords: seq[string] = @[]): untyped =
  ## A convenience wrapper to both generate a command-line dispatcher and then
  ## call the dispatcher & exit; Params are same as the ``dispatchGen`` macro.
  dispatchGen(pro, cmdName, doc, help, short, usage, cf, echoResult, noAutoEcho,
              positional, suppress, implicitDefault, mandatoryOverride,
              stopWords, dispatchName, mergeNames)
  cligenQuitAux(os.commandLineParams(), dispatchName, cmdName, pro, echoResult,
                noAutoEcho)

proc subCmdName(p: NimNode): string =
  if p.paramPresent("cmdName"):     #CLI author-specified
    result = $p.paramVal("cmdName")
  else:                             #1st elt of bracket
    result = if p[0].kind == nnkDotExpr: $p[0][^1]  #qualified (1-level)
             else: $p[0]                            #unqualified

template unknownSubcommand*(cmd: string, subCmds: seq[string]) =
  stderr.write "Unknown subcommand \"" & cmd & "\".  "
  let sugg = suggestions(cmd, subCmds, subCmds)
  if sugg.len > 0:
    stderr.write "Maybe you meant one of:\n\t" & join(sugg, " ") & "\n\n"
  else:
    stderr.write "It is not similar to defined subcommands.\n\n"
  stderr.write "Run again with subcommand \"help\" to get detailed usage.\n"
  quit(1)

template ambigSubcommand*(cb: CritBitTree[string], attempt: string) =
  stderr.write "Ambiguous subcommand \"", attempt, "\" matches:\n"
  stderr.write "  ", cb.valsWithPfx(attempt).join("\n  "), "\n"
  stderr.write "Run with no-argument or \"help\" for more details.\n"
  quit(1)

proc topLevelHelp*(srcBase: auto, subCmds: auto, subDocs: auto): string=
  var pairs: seq[seq[string]]
  for i in 0 ..< subCmds.len:
    pairs.add(@[subCmds[i], subDocs[i].replace("\n", " ")])
  """

  $1 {CMD}  [sub-command options & parameters]

where {CMD} is one of:

$2
$1 {-h|--help} or with no args at all prints this message.
$1 --help-syntax gives general cligen syntax help.
Run "$1 {help CMD|CMD --help}" to see help for just CMD.
Run "$1 help" to get *comprehensive* help.$3""" % [ srcBase,
  addPrefix("  ", alignTable(pairs, prefixLen=2)),
  (if clCfg.version.len > 0: "\nTop-level --version also available" else: "") ]

macro dispatchMultiGen*(procBkts: varargs[untyped]): untyped =
  ## Generate multi-cmd dispatch. ``procBkts`` are argLists for ``dispatchGen``.
  ## Eg., ``dispatchMultiGen([foo, short={"dryRun": "n"}], [bar, doc="Um"])``.
  let procBrackets = if procBkts.len < 2: procBkts[0] else: procBkts
  result = newStmtList()
  var prefix = "multi"
  if procBrackets[0][0].kind == nnkStrLit:
    prefix = procBrackets[0][0].strVal
  let srcBase = srcBaseName(procBkts)
  let multiId = ident(prefix)
  let subCmdsId = ident(prefix & "SubCmds")
  let subMchsId = ident(prefix & "SubMchs")
  let multiNmsId = ident(prefix & "multiNames")
  let subDocsId = ident(prefix & "SubDocs")
  result.add(quote do:
    {.push hint[GlobalVar]: off.}
    var `multiNmsId`: seq[string]
    var `subCmdsId`: seq[string] = @[ "help" ]
    var `subMchsId`: CritBitTree[string]
    `subMchsId`.incl("help", "help")
    var `subDocsId`: seq[string] = @[ "print comprehensive or per-cmd help" ]
    {.pop.})
  for p in procBrackets:
    if p[0].kind == nnkStrLit:
      continue
    let sCmdNm = p.subCmdName
    var c = newCall("dispatchGen")
    copyChildrenTo(p, c)
    if not c.paramPresent("usage"):
      c.add(newParam("usage", newStrLitNode(clUse)))
    if not c.paramPresent("mergeNames"):
      c.add(newParam("mergeNames", quote do: @[ `srcBase`, `sCmdNm` ]))
    if not c.paramPresent("docs"):
      c.add(newParam("docs", quote do: `subDocsId`.addr))
    result.add(c)
    result.add(newCall("add", subCmdsId, newStrLitNode(sCmdNm)))
    result.add(newCall("incl",
                 subMchsId, newCall("optionNormalize", newStrLitNode(sCmdNm)),
                            newCall("helpCase", newStrLitNode(sCmdNm))))
  let arg0Id = ident("arg0")
  let restId = ident("rest")
  let dashHelpId = ident("dashHelp")
  let helpSCmdId = ident("helpSCmdId")
  let cmdLineId = ident("cmdLine")
  let usageId = ident("usage")
  let prefixId = ident("prefix")
  var cases = newNimNode(nnkCaseStmt).add(arg0Id)
  var helpDump = newStmtList()
  for cnt, p in procBrackets:
    if p[0].kind == nnkStrLit:
      continue
    let sCmdNmS = p.subCmdName
    let disNm = if p.paramPresent("dispatchName"): $p.paramVal("dispatchName")
                else: "dispatch" & p.subCmdName  #XXX illegal chars?
    let disNmId = dispatchId(disNm, sCmdNmS, "")
    let sCmdNm = newStrLitNode(sCmdNmS)
    let sCmdEcR    = if p.paramPresent("echoResult"): p.paramVal("echoResult")
                     else: newLit(false)
    let sCmdNoAuEc = if p.paramPresent("noAutoEcho"): p.paramVal("noAutoEcho")
                     else: newLit(false)
    let sCmdUsage  = if p.paramPresent("usage"): p.paramVal("usage").strVal
                     else: clUse
    let mn = if p.paramPresent("mergeNames"): p.paramVal("mergeNames")
             else: quote do: @[ `srcBase` ] #, `sCmdNm` ]
    cases.add(newNimNode(nnkOfBranch).
              add(newCall("optionNormalize", sCmdNm)).add(quote do:
      cligenQuitAux(`restId`, `disNm`, `sCmdNmS`, p[0], `sCmdEcR`.bool,
                    `sCmdNoAuEc`.bool, `mn`)))
    let spc = if cnt + 1 < len(procBrackets): quote do: echo ""
              else: newNimNode(nnkEmpty)
    helpDump.add(quote do:
      if `disNm` in `multiNmsId`:
        cligenHelp(`disNmId`,`helpSCmdId`,`sCmdUsage`,`prefixId` & "  "); `spc`
      else:
        cligenHelp(`disNmId`, `dashHelpId`, `sCmdUsage`, `prefixId`); `spc`)
  cases.add(newNimNode(nnkElse).add(quote do:
    if `arg0Id` == "":
      if `cmdLineId`.len > 0: ambigSubcommand(`subMchsId`, `cmdLineId`[0])
      else: echo "Usage:\n  ", topLevelHelp(`srcBase`, `subCmdsId`, `subDocsId`)
    elif `arg0Id` == "help":
      if ("dispatch" & `prefix`) in `multiNmsId` and `prefix` != "multi":
        echo ("  $1 $2 subsubcommand [subsubcommand-opts & args]\n" &
              "    where subsubcommand syntax is:") % [ `srcBase`, `prefix` ]
      else:
        echo ("This is a multiple-dispatch command.  Top-level " &
              "--help/--help-syntax\nis also available.  Usage is like:\n" &
              "    $1 subcommand [subcommand-opts & args]\n" &
              "where subcommand syntaxes are as follows:\n") % [ `srcBase` ]
      let `dashHelpId` = @[ "--help" ]
      let `helpSCmdId` = @[ "help" ]
      `helpDump`
    else:
      unknownSubcommand(`arg0Id`, `subCmdsId`)))
  result.add(quote do:
    `multiNmsId`.add("dispatch" & `prefix`)
    proc `multiId`(`cmdLineId`: seq[string], `usageId`=clUse, `prefixId`="  ") =
      {.push hint[XDeclaredButNotUsed]: off.}
      let n = `cmdLineId`.len
      let `arg0Id` = if n > 0: `subMchsId`.lengthen `cmdLineId`[0] else: ""
      let `restId`: seq[string] = if n > 1: `cmdLineId`[1..<n] else: @[ ]
      `cases`)
  when defined(printDispatchMultiGen): echo repr(result)  # maybe print gen code

macro dispatchMultiDG*(procBkts: varargs[untyped]): untyped =
  let procBrackets = if procBkts.len < 2: procBkts[0] else: procBkts
  var prefix = "multi"
  let multiId = ident(prefix)
  result = newStmtList()
  result.add(newCall("dispatchGen", multiId))
  if procBrackets[0][0].kind == nnkStrLit:
    prefix = procBrackets[0][0].strVal
    let main = procBrackets[0]
    for e in 1 ..< main.len:
      result[^1].add(main[e])
  let subCmdsId = ident(prefix & "SubCmds")
  if not result[^1][0].paramPresent("stopWords"):
    result[^1].add(newParam("stopWords", subCmdsId))
  if not result[^1][0].paramPresent("dispatchName"):
    result[^1].add(newParam("dispatchName", newStrLitNode(prefix & "Subs")))
  if not result[^1][0].paramPresent("suppress"):
    result[^1].add(newParam("suppress", quote do: @[ "usage", "prefix" ]))
  let srcBase = srcBaseName(procBrackets)
  let subDocsId = ident(prefix & "SubDocs")
  if not result[^1][0].paramPresent("usage"):
    result[^1].add(newParam("usage", quote do:
      "Usage:\n  " & topLevelHelp(`srcBase`, `subCmdsId`, `subDocsId`)))
  when defined(printDispatchDG): echo repr(result)  # maybe print gen code

macro dispatchMulti*(procBrackets: varargs[untyped]): untyped =
  ## A wrapper to generate a multi-command dispatcher, then call it, and quit.
  var prefix = "multi"
  if procBrackets[0][0].kind == nnkStrLit:
    prefix = procBrackets[0][0].strVal
  let subCmdsId = ident(prefix & "SubCmds")
  let subMchsId = ident(prefix & "SubMchs")
  let SubsDispId = ident(prefix & "Subs")
  result = newStmtList()
  result.add(quote do: {.push warning[GCUnsafe]: off.})
  result.add(newCall("dispatchMultiGen", copyNimTree(procBrackets)))
  result.add(newCall("dispatchMultiDG", copyNimTree(procBrackets)))
  result.add(quote do:
    #`ps` is NOT mergeParams because we want typo suggestions for subcmd (with
    #options) based only on a CL user's actual *command line* entry.  Other srcs
    #are on their own.  This could be trouble if anyone wants commandLineParams
    #to NOT be the suffix of mergeParams, but we could also add a define switch.
    block:
     {.push hint[GlobalVar]: off.}
     {.push warning[ProveField]: off.}
     let ps = cast[seq[string]](commandLineParams())
     let ps0 = if ps.len >= 1: `subMchsId`.lengthen ps[0] else: ""
     let ps1 = if ps.len >= 2: `subMchsId`.lengthen ps[1] else: ""
     if ps.len>0 and ps0.len>0 and ps[0][0] != '-' and ps0 notin `subMchsId`:
       unknownSubcommand(ps[0], `subCmdsId`)
     elif ps.len > 0 and ps0.len == 0:
       ambigSubcommand(`subMchsId`, ps[0])
     elif ps.len == 2 and ps0 == "help":
       if ps1 in `subMchsId`: cligenQuit(`SubsDispId`(@[ ps1, "--help" ]))
       elif ps1.len == 0: ambigSubcommand(`subMchsId`, ps[1])
       else: unknownSubcommand(ps[1], `subCmdsId`)
     else:
       cligenQuit(`SubsDispId`())
     {.pop.}  #ProveField
     {.pop.}  #GlobalVar
    {.pop.}) #GcUnsafe
  when defined(printDispatchMulti): echo repr(result)  # maybe print gen code

macro initGen*(default: typed, T: untyped, positional="",
               suppress: seq[string] = @[], initName=""): untyped =
  ##This macro generates an ``init`` proc for object|tuples of type ``T`` with
  ##param names equal to top-level field names & default values from ``default``
  ##like ``init(field1=default.field1,...): T = result.field1=field1; ..``,
  ##except if ``fieldN==positional fieldN: typeN`` is used instead which in turn
  ##makes ``dispatchGen`` bind that ``seq`` to catch positional CL args.
  var ti = default.getTypeImpl
  case ti.typeKind:
  of ntyTuple: discard            #For tuples IdentDefs are top level
  of ntyObject: ti = ti[2]        #For objects, descend to the nnkRecList
  else: error "default value is not a tuple or object"
  let empty = newNimNode(nnkEmpty)
  let suppressed = toStrSeq(suppress)
  var params = @[ quote do: `T` ] #Return type
  var assigns = newStmtList()     #List of assignments 
  for kid in ti.children:         #iterate over fields
    if kid.kind != nnkIdentDefs: warning "case objects unsupported"
    let nm = kid[0].strVal
    if nm in suppressed: continue
    let id = ident(nm)
    let argId = ident("arg"); let obId = ident("ob")
    params.add(if nm == positional.strVal: newIdentDefs(id, kid[1], empty)
               else: newIdentDefs(id, empty, quote do: `default`.`id`))
    let r = ident("result") #Someday: assigns.add(quote do: result.`id` = `id`)
    let sid = ident("set" & nm); let sidEq = ident("set" & nm & "=")
    assigns.add(quote do:
      proc `sidEq`(`obId`: var `T`, `argId` = `default`.`id`) = ob.`id`=`argId`
      `r`.`sid` = `id`)
  let initNm = if initName.strVal.len > 0: initName.strVal else: "init"
  result = newProc(name = ident(initNm), params = params, body = assigns)
  when defined(printInit): echo repr(result)  # maybe print gen code

template initFromCL*[T](default: T, cmdName: string="", doc: string="",
    help: typed={}, short: typed={}, usage: string=clUsage, cf: ClCfg=clCfg,
    positional="", suppress:seq[string] = @[], mergeNames:seq[string] = @[]): T=
  ## Like ``dispatch`` but only ``quit`` when user gave bad CL, --help,
  ## or --version.  On success, returns ``T`` populated from object|tuple
  ## ``default`` and then from the ``mergeNames``/the command-line.  Top-level
  ## fields must have types with ``argParse`` & ``argHelp`` overloads.  Params
  ## to this common to ``dispatchGen`` mean the same thing.  The inability here
  ## to distinguish between syntactically explicit assigns & Nim type defaults
  ## eliminates several features and makes the `positional` default be empty.
  proc callIt(): T =
    initGen(default, T, positional, suppress, "ini")
    dispatchGen(ini, cmdName, doc, help, short, usage, cf, false, false,
                AUTO, @[], @[], @[], @[], "x", mergeNames)
    try: result = x()
    except HelpOnly, VersionOnly: quit(0)
    except ParseError: quit(1)
  callIt()      #inside proc is not strictly necessary, but probably safer.

proc versionFromNimble*(nimbleContents: string): string =
  ## const foo = staticRead "relPathToDotNimbleFile"; use versionFromNimble(foo)
  result = "unparsable nimble version"
  for line in nimbleContents.split("\n"):
    if line.startsWith("version"):
      let cols = line.split('=')
      result = cols[1].strip()[1..^2]
      break

proc mergeParams*(cmdNames: seq[string],
                  cmdLine=commandLineParams()): seq[string] =
  ##This is a pass-through parameter merge to provide a hook for CLI authors to
  ##create the ``seq[string]`` to be parsed from any run-time sources (likely
  ##based on ``cmdNames``) that they would like.  In a single ``dispatch``
  ##context, ``cmdNames[0]`` is the ``cmdName`` while in a ``dispatchMulti``
  ##context it is ``@[ <mainCommand>, <subCommand> ]``.
  cmdLine

include cligen/oldAPI   #TEMPORARY SUPPORT FOR THE OLD CALLING CONVENTION
