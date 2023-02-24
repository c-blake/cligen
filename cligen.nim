when not (defined(cgCfgNone) and defined(cgNoColor)):
  {.push hint[Performance]: off.}     # Silence RstToken copy warning
when (NimMajor,NimMinor,NimPatch) > (0,20,2):
  {.push warning[UnusedImport]: off.} # This is only for gcarc
import std/[os, macros, tables, strutils, critbits], system/ansi_c,
       cligen/[parseopt3, argcvt, textUt, sysUt, macUt, humanUt, gcarc]
export commandLineParams, lengthen, initOptParser, next, optionNormalize,
       ArgcvtParams, argParse, argHelp, getDescription, join, `%`, CritBitTree,
       incl, valsWithPfx, contains, addPrefix, wrap, TextTab, alignTable,
       suggestions, strip, split, helpCase, postInc, delItem, fromNimble,
       summaryOfModule, docFromModuleOf, docFromProc, match, wrapWidth

# NOTE: `helpTmpl`, `clCfgInit`, and `syntaxHelp` can all be overridden on a per
# client project basis with a local `cligen/` before cligen-actual in `path`.
include cligen/helpTmpl           #Pull in various help template strings
include cligen/syntaxHelp

type    # Main defns CLI authors need be aware of (besides top-level API calls)
  ClHelpCol* = enum clOptKeys, clValType, clDflVal, clDescrip

  ClSIGPIPE* = enum spRaise="raise", spPass="pass", spIsOk="isOk"

  ClAlias* = tuple[long: string, short: char, helpStr: string,
                   dfl: seq[seq[string]]]         ## User CL aliases

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
    longPfxOk*:   bool           ## ``parseopt3.initOptParser`` parameter
    stopPfxOk*:   bool           ## ``parseopt3.initOptParser`` parameter
    hTabSuppress*: string        ## Magic val for per-param help to suppress
    helpAttr*:    Table[string, string] ## Text attrs for each help area
    helpAttrOff*: Table[string, string] ## Text attr offs for each help area
    noHelpHelp*: bool            ## Elide --help, --help-syntax from help table
    useHdr*:      string         ## Override of const usage header template
    use*:         string         ## Override of const usage template
    useMulti*:    string         ## Override of const subcmd table template
    helpSyntax*:  string         ## Override of const syntaxHelp string
    render*:      proc(s: string): string ## string->string help transformer
    widthEnv*:    string         ## name of environment var for width override
    sigPIPE*:     ClSIGPIPE      ## `dispatch` use allows end-user SIGPIPE ctrl

  HelpOnly*    = object of CatchableError ## Ok Ctl Flow Only For --help
  VersionOnly* = object of CatchableError ## Ok Ctl Flow Only For --version
  ParseError*  = object of CatchableError ## CL-Syntax Err from generated code
  HelpError*   = object of CatchableError ## User-Syntax/Semantic Err; ${HELP}

proc descape(s: string): string =
  for c, escaped in s.descape: result.add c

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
                 '|', '~', '^', '$', '#', '<', '>', '?' },
  longPfxOk:   true,
  stopPfxOk:   true,
  hTabSuppress: "CLIGEN-NOHELP",
  helpAttr:    initTable[string,string](),
  helpAttrOff: initTable[string,string](),
  helpSyntax:  syntaxHelp,
  render:      descape,     # Often set in `clCfgInit`, eg. to `rstMdToSGR`
  widthEnv:    "CLIGEN_WIDTH",
  sigPIPE:     spIsOk)

var cgParseErrorExitCode* = 1
{.pop.}

const builtinOptions = ["help", "helpsyntax", "version"]

proc toInts*(x: seq[ClHelpCol]): seq[int] =
  ##Internal routine to convert help column enums to just ints for `alignTable`.
  for e in x: result.add(int(e))

when defined(cgCfgToml):    # An include helpTmpl and syntaxHelp
  include cligen/clCfgToml  # Trade parsetoml dependency for better documention
elif not defined(cgCfgNone):
  include cligen/clCfgInit  # Just use stdlib parsecfg

proc onCols*(c: ClCfg): seq[string] =
  ##Internal routine to map help table color specs to strings for `alignTable`.
  for e in ClHelpCol.low..ClHelpCol.high:
    result.add c.helpAttr.getOrDefault($e, "")

proc offCols*(c: ClCfg): seq[string] =
  ##Internal routine to map help table color specs to strings for `alignTable`.
  for e in ClHelpCol.low..ClHelpCol.high:
    result.add c.helpAttrOff.getOrDefault($e, "")

proc ha0*(key: string, c=clCfg): string = c.helpAttr.getOrDefault(key, "")
  ## Internal routine to access `c.helpAttr`
proc ha1*(key: string, c=clCfg): string = c.helpAttrOff.getOrDefault(key, "")
  ## Internal routine to access `c.helpAttrOff`

type    #Utility types/code for generated parser/dispatchers for parseOnly mode
  ClStatus* = enum clBadKey,                        ## Unknown long key
                   clBadVal,                        ## Unparsable value
                   clNonOption,                     ## Unexpected non-option
                   clMissing,                       ## Required but missing
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

var setByParseDum: seq[ClParse]; let cgSetByParseNil* = setByParseDum.addr
var varSeqStrDum: seq[string]  ; let cgVarSeqStrNil*  = varSeqStrDum.addr

proc quits*(s: int) = quit(if s < -128: -128 elif s > 127: 127 else: s)
  ## quits)afe|s)aturating is for non-literal/maybe big input for compatibility
  ## w/older Nim stdlibs.  Value is clipped to -128..127.  Note that Unix shells
  ## often map a signaled exit to SIGNUM-128, e.g. 2-128 for SIGINT.

proc die0(s: cint) {.noconv, used.} = quit(0)
proc SIGPIPE_isOk*() =
  ## Install signal handler to exit success upon OS posting SIGPIPE.  This is
  ## more or less what (non-network) programs/users "expect".
  when declared(SIGPIPE): c_signal(SIGPIPE, die0)

proc SIGPIPE_pass*() =
  ## Restore default signal disposition to allow OS to post SIGPIPE and likely
  ## terminate with non-zero exit status (typically 141=128+signo13).  This
  ## optimizes for "no surprises" behavior of exec()d code reasonably expecting
  ## to inherit a near default SIGPIPE disposition.
  when declared(SIGPIPE) and declared(SIG_DFL): c_signal(SIGPIPE, SIG_DFL)

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

proc containsParam(fpars: NimNode, key: NimNode): bool =
  for declIx in 1 ..< len(fpars):       #default for result=false
    let idefs = fpars[declIx]           #Use similar logic to formalParamExpand
    for i in 0 ..< len(idefs) - 3:      #..since`suppress` is a seq we check.
      if maybeDestrop(idefs[i]) == key: return true
    if maybeDestrop(idefs[^3]) == key: return true

proc formalParamExpand(fpars: NimNode, n: auto,
                       suppress: seq[NimNode]= @[]): NimNode =
  # a,b,..,c:type [maybe=val] --> a:type, b:type, ..., c:type [maybe=val]
  result = newNimNode(nnkFormalParams)
  result.add(fpars[0])                                  # just copy ret value
  for p in suppress:
    if not fpars.containsParam(p):
      error repr(n[0]) & " has no param matching `suppress` key \"" & $p & "\""
  for declIx in 1 ..< len(fpars):
    let idefs = fpars[declIx]
    for i in 0 ..< len(idefs) - 3:
      if not suppress.has(idefs[i]):
        result.add(newIdentDefs(idefs[i], idefs[^2]))
    if not suppress.has(idefs[^3]):
      result.add(newIdentDefs(idefs[^3], idefs[^2], idefs[^1]))

proc formalParams(n: NimNode, suppress: seq[NimNode]= @[]): NimNode =
  for kid in n: #Extract expanded formal parameter list from getImpl return val.
    if kid.kind == nnkFormalParams:
      return formalParamExpand(kid, n, suppress)
  error "formalParams requires a proc argument."
  return nil                #not-reached

iterator AListPairs(alist: NimNode, msg: string): (NimNode, NimNode) =
  if alist.kind == nnkSym:
    let imp = alist.getImpl
    when (NimMajor,NimMinor,NimPatch) >= (1,7,3):
      if imp.len < 3 or imp[2].len < 2 or imp[2][1].len < 2: # Be more precise?
        error msg & " initializer must be a static/const {}.toTable construct"
      let tups = imp[2][1][1]
    else:
      if imp.len < 2 or imp[1].len < 2: # This condition should be more precise
        error msg & " initializer must be a static/const {}.toTable construct"
      let tups = imp[1][1]
    for tup in tups:
      if tup[0].intVal != 0:
        yield(tup[1], tup[2])
  else:
    for ph in alist: yield (ph[1][0], ph[1][1])

proc parseHelps(helps: NimNode, proNm: auto, fpars: auto):
    Table[string, (string, string)] =
  result = initTable[string, (string, string)]() #help key & text for any param
  for ph in AListPairs(helps, "`help`"):
    let k = ph[0].toString.optionNormalize
    if not fpars.containsParam(ident(k)) and k notin builtinOptions:
      error $proNm & " has no param matching `help` key \"" & k & "\""
    result[k] = (ph[0].toString, ph[1].toString)

proc parseShorts(shorts: NimNode, proNm: auto, fpars: auto): Table[string,char]=
  result = initTable[string, char]()  #table giving user-specified short option
  for ls in AListPairs(shorts, "`short`"):
    let k = ls[0].toString.optionNormalize
    if k.len>0 and not fpars.containsParam(k.ident) and k notin builtinOptions:
      error $proNm & " has no param matching `short` key \"" & k & "\""
    if ls[1].kind notin {nnkCharLit, nnkIntLit}:
      error "`short` value for \"" & k & "\" not a `char` lit"
    result[k] = if shorts.kind==nnkSym: ls[1].toInt.char else: ls[1].intVal.char

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
    used.incl sh
  for i in 1 ..< len(fpars):                 # [0] is proc, not desired here
    if i == posIx: continue                  # positionals get no option char
    let parNm = optionNormalize($fpars[i][0])
    if parNm.len == 1:
      if parNm notin userSpec:
        result[parNm] = parNm[0]
      if parNm[0] in used and result[parNm] != parNm[0]:
        error "cannot use unabbreviated param name '" &
              $parNm[0] & "' as a short option"
      used.incl parNm[0]
  for i in 1 ..< len(fpars):                 # [0] is proc, not desired here
    if i == posIx: continue                  # positionals get no option char
    let parNm = optionNormalize($fpars[i][0])
    if parNm.len == 1 and parNm[0] == result["help"]:
      error "`"&parNm&"` collides with `short[\"help\"]`.  Change help short."
    let sh = parNm[0]                        # abbreviation is 1st character
    if sh notin used and parNm notin result: # still available
      result[parNm] = sh
      used.incl(sh)
  var tmp = result        #One might just put sh != '\0' above, but this lets
  for k, v in tmp:        #CLI authors also block -h via short={"help": '\0'}.
    if v == '\0': result.del(k)

const AUTO = "\0"             #Just some "impossible-ish" identifier

proc posIxGet(positional: string, fpars: NimNode): int =
  if positional == "":  # Find proc param slot for optional positional CL args
    return -1           # Empty string means deactivate auto identification.
  if positional != AUTO:
    result = findByName(ident(positional), fpars)
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

proc got(a: NimNode): bool =
  (a.len == 2 and a[1].len == 2 and a[1][0].len == 2 and a[1][1].len == 2 and
   a[1][0][1].len == 4 and a[1][1][1].len == 4)

macro dispatchGen*(pro: typed{nkSym}, cmdName: string="", doc: string="",
  help: typed={}, short: typed={}, usage: string=clUse, cf: ClCfg=clCfg,
  echoResult=false, noAutoEcho=false, positional: static string=AUTO,
  suppress: seq[string] = @[], implicitDefault: seq[string] = @[],
  dispatchName="", mergeNames: seq[string] = @[], alias: seq[ClAlias] = @[],
  stopWords: seq[string] = @[], noHdr=false,
  docs: ptr var seq[string]=cgVarSeqStrNil,
  setByParse: ptr var seq[ClParse]=cgSetByParseNil): untyped =
  ##Generate command-line dispatcher for proc ``pro`` named ``dispatchName``
  ##(defaulting to ``dispatchPro``) with generated help/syntax guided by
  ##``cmdName``, ``doc``, and ``cf``.  Parameters with no explicit default in
  ##the proc become required command arguments while those with default values
  ##become command options. Each proc parameter type needs in-scope ``argParse``
  ##& ``argHelp`` procs.  ``cligen/argcvt`` defines them for basic types & basic
  ##collections (``int``, ``string``, ``enum``, .., ``seq[T], set[T], ..``).
  ##
  ##``help`` is a ``{(paramNm, str)}`` of per-param help, eg. ``{"quiet": "be
  ##quiet"}``.  Often, only these help strings are needed for a decent CLI.
  ##A row of the help table can be suppressed from showing by setting ``str``
  ##to a magic ``clCfg.hTabSuppress`` value (defaults to ``"CLIGEN-NOHELP"``,
  ##but is customizable).
  ##
  ##``short`` is a ``{(paramNm, char)}`` of per-param single-char option keys.
  ##Setting a parameter value to ``'\0'`` suppresses the assignment of a short
  ##option. Suppress all short options by passing an empty key: ``{ "": ' ' }``.
  ##
  ##``help`` & ``short`` definitions outside a call require explicit ``toTable``
  ## (from ``std/tables``) conversions.
  ##
  ##``usage`` is a help template interpolating $command $args $doc $options.
  ##
  ##``cf`` controls whole program aspects of generated CLIs. See ``ClCfg`` docs.
  ##
  ##Default exit protocol is: quits(int(result)) or (echo $result or discard;
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
  ##to the Nim default value for a type, rather than becoming required, when
  ##they lack an explicit initializer.
  ##
  ##``stopWords`` is a ``seq[string]`` of words beyond which ``-.*`` no longer
  ##signifies an option (like the common sole ``--`` command argument).
  ##
  ##``mergeNames`` gives the ``cmdNames`` param passed to ``mergeParams``, which
  ##defaults to ``@[cmdName]`` if ``mergeNames`` is ``@[]``.
  ##
  ##``alias`` is ``@[]`` | 2-seq of ``(string,char,string)`` 3-tuples specifying
  ##(Long, Short opt keys, Help) to [Define,Reference] aliases.  This lets CL
  ##users define aliases early in ``mergeParams`` sources (e.g. cfg files/evars)
  ##& reference them later. Eg. if ``alias[0][0]=="alias" and alias[1][1]=='a'``
  ##then ``--alias:k='-a -b' -ak`` expands to ``@["-a", "-b"]``.
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
  let fpars = formalParams(impl, toIdSeq(suppress))
  var cmtDoc = toString(doc)
  if cmtDoc.len == 0:                   # allow caller to override commentDoc
    collectComments(cmtDoc, impl)
    cmtDoc = strip(cmtDoc)
  let cf = cf #sub-scope quote-do's cannot access macro args w/o shadow locals.
  let setByParse = setByParse
  let proNm = $pro                      # Name of wrapped proc
  let cName = if cmdName.toString.len == 0: proNm else: cmdName.toString
  let disNm = dispatchId(dispatchName.toString, cName, proNm) # Name of wrapper
  let helps = parseHelps(help, proNm, fpars)
  let posIx = posIxGet(positional, fpars) #param slot for positional cmd args|-1
  let shOpt = dupBlock(fpars, posIx, parseShorts(short, proNm, fpars))
  let shortH = shOpt["help"]
  var spars = copyNimTree(fpars)        # Create shadow/safe suffixed params.
  var dpars = copyNimTree(fpars)        # Create default suffixed params.
  var mandatory = newSeq[int]()         # At the same time, build metadata on..
  let implDef = toIdSeq(implicitDefault)
  for p in implDef:
    if not fpars.containsParam(p):
      error $proNm&" has no param matching `implicitDefault` key \"" & $p & "\""
  var hasVsn = false
  for i in 1 ..< len(fpars):            #..non-defaulted/mandatory parameters.
    if ident($(fpars[i][0])) == ident("version"):
      hasVsn = true
    dpars[i][0] = ident($(fpars[i][0]) & "ParamDefault")   # unique suffix
    spars[i][0] = ident($(fpars[i][0]) & "ParamDispatch")  # unique suffix
    if fpars[i][2].kind == nnkEmpty:
      if i == posIx:                    # No initializer; Add @[]
        spars[posIx][2] = prefix(newNimNode(nnkBracket), "@")
      else:
        if fpars[i][1].kind == nnkEmpty:
          error("parameter `" & $(fpars[i][0]) &
                "` has neither a type nor a default value")
        if not implDef.has(fpars[i][0]):
          mandatory.add(i)
  let posNoId = ident("posNo")          # positional arg number
  let keyCountId = ident("keyCount")    # id for keyCount table
  let usageId = ident("usage")          # gen proc parameter
  let cmdLineId = ident("cmdline")      # gen proc parameter
  let vsnSh = if "version" in shOpt: $shOpt["version"] else: "\0"
  let prefixId = ident("prefix")        # local help prefix param
  let prsOnlyId = ident("parseOnly")    # flag to only produce a parse vector
  let skipHelp = ident("skipHelp")      # flag to control --help/--help-syntax
  let noHdrId = ident("noHdr")          # flag to control using `clUseHdr`
  let pId = ident("p")                  # local OptParser result handle
  let allId = ident("allParams")        # local list of all parameters
  let cbId = ident("crbt")              # CritBitTree for prefix lengthening
  let mandId = ident("mand")            # local list of mandatory parameters
  let apId = ident("ap")                # ArgcvtParams
  var callIt = newNimNode(nnkCall)      # call of wrapped proc in genproc
  callIt.add(pro)
  let shortHlp = newStrLitNode($shortH)
  let setByParseId = ident("setByP")    # parse recording var seq
  let b0 = ident("b0"); let b1 = ident("b1")
  let g0 = ident("g0"); let g1 = ident("g1")
  let es = newStrLitNode("")
  let aliasesId = ident("aliases")      # [key]=>seq[string] meta param table
  let aliasSnId = ident("aliasSeen")    # flag saying *any* alias was used
  let dflSub    = ident("dflSub")       # default alias if *no* alias was used
  let provideId = ident("provideDflAlias") # only use default alias @top level
  let aliasDefL = if alias.got: alias[1][0][1][0] else: es
  let aliasDefN = if alias.got:optionNormalize(alias[1][0][1][0].strVal) else:""
  let aliasDefS = if alias.got: toStrIni(alias[1][0][1][1].intVal) else: es
  let aliasDefH = if alias.got: alias[1][0][1][2] else: es
  let aliasDefD = if alias.got: alias[1][0][1][3] else: es
  let aliasRefL = if alias.got: alias[1][1][1][0] else: es
  let aliasRefN = if alias.got:optionNormalize(alias[1][1][1][0].strVal) else:""
  let aliasRefS = if alias.got: toStrIni(alias[1][1][1][1].intVal) else: es
  let aliasRefH = if alias.got: alias[1][1][1][2] else: es
  let aliasRefD = if alias.got: alias[1][1][1][3] else: es
  let aliases = if alias.got: quote do:
                    var `aliasSnId` = false
                    var `aliasesId`: CritBitTree[seq[string]]
                    for d in `aliasDefD`:
                      if d.len > 1: `aliasesId`[d[0]] = d[1 .. ^1]
                    var `dflSub`: seq[string] = if `aliasRefD`.len>0:
                                                  `aliasRefD`[0] else: @[]
                else: newNimNode(nnkEmpty)
  let aliasesCallDfl = if alias.got: quote do:
                    if `provideId` and not `aliasSnId` and `dflSub`.len > 0:
  #XXX Doing this feature right needs 2 OptParser passes. {Default alias should
  #be processed first not last to not clobber earlier cfg/CL actual settings,
  #but cannot know it is needed without first checking the whole CL.}
                      parser(move(`dflSub`), `provideId`=false)
                else: newNimNode(nnkEmpty)

  let helpHelp = helps.getOrDefault("help",
                   ("help", "print this cligen-erated help"))
  let helpSyn = helps.getOrDefault("helpsyntax", ("help-syntax",
                  "advanced: prepend,plurals,.."))
  let helpVsn = helps.getOrDefault("version", ("version", "print version"))

  proc initVars0(): NimNode =           # init vars & build help str
    result = newStmtList()
    let tabId = ident("tab")            # local help table var
    result.add(quote do:
      var `apId`: ArgcvtParams
      `apId`.val4req = `cf`.hTabVal4req
      let shortH = `shortHlp`
      var `allId`: seq[string] =
        if `cf`.helpSyntax.len > 0: @[ "help", "help-syntax" ] else: @[ "help" ]
      var `cbId`: CritBitTree[string]
      `cbId`.incl(optionNormalize("help"), "help")
      if `cf`.helpSyntax.len > 0:
        `cbId`.incl(optionNormalize("help-syntax"), "help-syntax")
      var `mandId`: seq[string]
      var `tabId`: TextTab = @[]
      let helpHelpRow = @[ "-"&shortH&", --help", "", "", `helpHelp`[1] ]
      let `skipHelp` = `skipHelp` or `cf`.noHelpHelp
      if `skipHelp`:                    # auto-skip help help for `helpDump`
        if shortH != "h" and `helpHelp`[1] != `cf`.hTabSuppress:
          `tabId`.add(helpHelpRow)
      elif `helpHelp`[1] != `cf`.hTabSuppress: `tabId`.add(helpHelpRow)
      if `cf`.helpSyntax.len > 0 and `helpSyn`[1] != `cf`.hTabSuppress and
         not `skipHelp`:
        `tabId`.add(@[ "--" & `helpSyn`[0], "", "", `helpSyn`[1] ])
      `apId`.shortNoVal = { shortH[0] }               # argHelp(bool) updates
      `apId`.longNoVal = @[ "help", "help-syntax" ]   # argHelp(bool) appends
      let `setByParseId`: ptr seq[ClParse] = `setByParse`
      let `b0` = ha0("bad" , `cf`); let `b1` = ha1("bad" , `cf`)
      let `g0` = ha0("good", `cf`); let `g1` = ha1("good", `cf`)
      {.push warning[GCUnsafe]: off.} # See github.com/c-blake/cligen/issues/92
      proc mayRend(x: string): string = # {.gcsafe.} clCfg access
        if `cf`.render != nil: `cf`.render(x) else: x
      {.pop.})
    result.add(quote do:
      if `cf`.version.len > 0:
        `allId`.add "version"
        `cbId`.incl(optionNormalize("version"), "version")
        `apId`.parNm = "version"; `apId`.parSh = `vsnSh`
        `apId`.parReq = 0; `apId`.parRend = `helpVsn`[0]
        if `helpVsn`[1] != `cf`.hTabSuppress:
          `tabId`.add(argHelp(false, `apId`) & `helpVsn`[1]))
    if aliasDefL.strVal.len > 0 and aliasRefL.strVal.len > 0:
      result.add(quote do:              # add opts for user alias system
        `cbId`.incl(optionNormalize(`aliasDefL`), `aliasDefL`)
        `apId`.parNm = `aliasDefL`; `apId`.parSh = `aliasDefS`
        `apId`.parReq = 0; `apId`.parRend = `apId`.parNm
        `tabId`.add(argHelp("", `apId`) & `aliasDefH`)
        `cbId`.incl(optionNormalize(`aliasRefL`), `aliasRefL`)
        `apId`.parNm = `aliasRefL`; `apId`.parSh = `aliasRefS`
        `apId`.parReq = 0; `apId`.parRend = `apId`.parNm
        `tabId`.add(argHelp("", `apId`) & `aliasRefH`) )
    let (posNm, posHlp, posTy) = if posIx != -1:
        let kH = helps.getOrDefault(optionNormalize($fpars[posIx][0]), ("",""))
        let ty = if fpars[posIx][1].kind == nnkSym: fpars[posIx][1].getImpl.repr
                 else: fpars[posIx][1][1].strVal
        if kH[0].len != 0: (kH[0], kH[1], ty)
        else: ($fpars[posIx][0], "", ty)
      else: ("", "", "")
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
         `apId`.parNm = `parNm`; `apId`.parSh = `sh`; `apId`.parReq = ord(`isReq`)
         `apId`.parRend = if `hky`.len>0: `hky` else:helpCase(`parNm`,clLongOpt)
         let descr = getDescription(`defVal`, `parNm`, `hlp`)
         if descr != `cf`.hTabSuppress:
           `tabId`.add(argHelp(`defVal`, `apId`) & mayRend(descr))
         if `apId`.parReq != 0: `tabId`[^1][2] = `apId`.val4req
         `cbId`.incl(optionNormalize(`parNm`), move(`apId`.parRend))
         `allId`.add(helpCase(`parNm`, clLongOpt)))
        if isReq:
          result.add(quote do: `mandId`.add(`parNm`))
    result.add(quote do:                  # build one large help string
      let ww = wrapWidth(`cf`.widthEnv)
      let indentDoc = addPrefix(`prefixId`, wrap(mayRend(`cmtDoc`), ww,
                                                 prefixLen=`prefixId`.len))
      proc hl(tag, val: string): string = # {.gcsafe.} clCfg access
        (`cf`.helpAttr.getOrDefault(tag, "") & val &
         `cf`.helpAttrOff.getOrDefault(tag, ""))
      let posHelp = if `posHlp`.len != 0: `posHlp`
                    elif `posNm`.len == 0: ""
                    else: "[" & hl("clOptKeys", `posNm`) & ": " &
                          hl("clValType", `posTy`) & "...]"
      let use = if `noHdrId`:
                  if `usageId`.len > 0: `usageId` else: `cf`.use
                else:
                  (if `cf`.useHdr.len > 0: `cf`.useHdr else: clUseHdr) &
                    (if `usageId`.len > 0: `usageId` else: `cf`.use)
      let argStart = "[" & (if `mandatory`.len>0: `apId`.val4req&"," else: "") &
                     "optional-params]"
      `apId`.help = use % ["doc",     hl("doc", indentDoc),
                           "command", hl("cmd", `cName`),
                           "args",  hl("args",argStart & " " & posHelp.mayRend),
                           "options", addPrefix(`prefixId` & "  ",
                              alignTable(`tabId`, 2*len(`prefixId`) + 2,
                                         `cf`.hTabColGap, `cf`.hTabMinLast,
                                         `cf`.hTabRowSep, toInts(`cf`.hTabCols),
                                         `cf`.onCols, `cf`.offCols, width=ww)) ]
      if `apId`.help.len > 0 and `apId`.help[^1] != '\n':   #ensure newline @end
        `apId`.help &= "\n"
      if len(`prefixId`) > 0:             # to indent help in a multicmd context
        `apId`.help = addPrefix(`prefixId`, `apId`.help))

  proc optCases0(): NimNode =
    result = newNimNode(nnkCaseStmt).add(quote do:
      if p.kind == cmdLongOption: lengthen(`cbId`, `pId`.key, `cf`.longPfxOk)
      else: `pId`.key)
    result.add(newNimNode(nnkOfBranch).add(
      newStrLitNode("help"), shortHlp).add(
        quote do:
          if cast[pointer](`setByParseId`) != cgSetByParseNil:
            `setByParseId`[].add(("help", "", `apId`.help, clHelpOnly))
          if not `prsOnlyId`:
            stdout.write(`apId`.help); raise newException(HelpOnly, "")))
    result.add(newNimNode(nnkOfBranch).add(
      newStrLitNode("helpsyntax")).add(
        quote do:
          if cast[pointer](`setByParseId`) != cgSetByParseNil:
            `setByParseId`[].add(("helpsyntax","", #COPY
                                  `cf`.helpSyntax[0..^1], clHelpOnly))
          if not `prsOnlyId`:
            stdout.write(`cf`.helpSyntax); raise newException(HelpOnly, "")))
    if not hasVsn:
      result.add(newNimNode(nnkOfBranch).add(
        newStrLitNode("version"), newStrLitNode(vsnSh)).add(
          quote do:
            if cast[pointer](`setByParseId`) != cgSetByParseNil:
              `setByParseId`[].add(("version", "", #COPY
                                    `cf`.version[0..^1], clVersionOnly))
            if not `prsOnlyId`:
              if `cf`.version.len > 0:
                stdout.write(`cf`.version, "\n")
                raise newException(VersionOnly, "")
              else:
                stdout.write("Unknown version\n")
                raise newException(VersionOnly, "")))
    if aliasDefL.strVal.len > 0 and aliasRefL.strVal.len > 0: #CL user aliases
      result.add(newNimNode(nnkOfBranch).add(
        newStrLitNode(aliasDefN), aliasDefS).add(
          quote do:
            let cols = `pId`.val.split('=', 1)   #split on 1st '=' only
            try: `aliasesId`[cols[0].strip] = parseCmdLine(cols[1].strip)
            except CatchableError: stderr.write "ignored bad alias: ",
                                   cols[0].strip, " = ", cols[1].strip, "\n"))
      result.add(newNimNode(nnkOfBranch).add(
        newStrLitNode(aliasRefN), aliasRefS).add(
          quote do:
            `aliasSnId` = true        #true for even unsuccessful attempted ref
            var msg: string
            let sub = `aliasesId`.match(`pId`.val, "alias ref", msg)
            if msg.len > 0:
              if cast[pointer](`setByParseId`) != cgSetByParseNil:
                `setByParseId`[].add((move(`pId`.key), move(`pId`.val),
                                      move(msg), clBadKey))
              if not `prsOnlyId`:
                stderr.write msg
                let t = if msg.startsWith "Ambig": "Ambiguous" else: "Unknown"
                raise newException(ParseError, t & " alias ref")
            else:
              parser(sub.val) ))
    for i in 1 ..< len(fpars):                # build per-param case clauses
      if i == posIx: continue                 # skip variable len positionals
      let parNm  = $fpars[i][0]
      let lopt   = optionNormalize(parNm)
      let spar   = spars[i][0]
      let dpar   = dpars[i][0]
      let apCall = quote do:
        `apId`.key = `pId`.key
        `apId`.val = `pId`.val
        `apId`.sep = `pId`.sep
        `apId`.parNm = `parNm`
        `apId`.parRend = helpCase(`parNm`, clLongOpt)
        `keyCountId`.inc(`parNm`)
        `apId`.parCount = `keyCountId`[`parNm`]
        if cast[pointer](`setByParseId`) != cgSetByParseNil:
          if argParse(`spar`, `dpar`, `apId`):
            `setByParseId`[].add((`parNm`, move(`pId`.val), "", clOk))
          else:
            `setByParseId`[].add((`parNm`, move(`pId`.val),
                                 "Cannot parse arg to " & `apId`.key, clBadVal))
        if not `prsOnlyId`:
          if not argParse(`spar`, `dpar`, `apId`):
            stderr.write `apId`.msg
            raise newException(ParseError, "Cannot parse arg to " & `apId`.key)
        discard delItem(`mandId`, `parNm`)
      if lopt in shOpt and lopt.len > 1:      # both a long and short option
        let parShOpt = $shOpt.getOrDefault(lopt)
        result.add(newNimNode(nnkOfBranch).add(
          newStrLitNode(lopt), newStrLitNode(parShOpt)).add(apCall))
      else:                                   # only a long option
        result.add(newNimNode(nnkOfBranch).add(newStrLitNode(lopt)).add(apCall))
    let ambigReport = quote do:
      let ks = `cbId`.valsWithPfx(p.key)
      let msg=("Ambiguous long option prefix \"" & `b0` & "$1" & `b1`  & "\"" &
       " matches:\n  " & `g0` & "$2" & `g1` & " ")%[`pId`.key,ks.join("\n  ")] &
       "\nRun with " & `g0` & "--help" & `g1` & " for more details.\n"
      if cast[pointer](`setByParseId`) != cgSetByParseNil:
        `setByParseId`[].add((move(`pId`.key), move(`pId`.val), msg, clBadKey))
      if not `prsOnlyId`:
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
        if sugg.len > 0: mb &= "Maybe you meant one of:\n\t" & `g0` &
                               join(sugg, " ") & `g1` & "\n\n"
      let msg=("Unknown "&k&" option: \"" & `b0` & `pId`.key & `b1` & "\"\n\n" &
               mb & "Run with " & `g0` & "--help" & `g1` & " for full usage.\n")
      if cast[pointer](`setByParseId`) != cgSetByParseNil:
        `setByParseId`[].add((move(`pId`.key), move(`pId`.val), msg, clBadKey))
      if not `prsOnlyId`:
        stderr.write(msg)
        raise newException(ParseError, "Unknown option")))

  proc nonOpt0(): NimNode =
    result = newStmtList()
    if posIx != -1:                           # code to parse non-option args
      result.add(newNimNode(nnkCaseStmt).add(quote do: postInc(`posNoId`)))
      let posId = spars[posIx][0]
      let tmpId = ident("tmp" & $posId)
      result[0].add(newNimNode(nnkElse).add(quote do:
        var `tmpId`: type(`posId`[0])
        `apId`.key = "positional $" & $`posNoId`
        `apId`.val = `pId`.key
        `apId`.sep = "="
        `apId`.parNm = `apId`.key
        `apId`.parRend = helpCase(`apId`.key, clLongOpt)
        `apId`.parCount = 1
        let msg = "Cannot parse " & `apId`.key
        if cast[pointer](`setByParseId`) != cgSetByParseNil:
          if argParse(`tmpId`,`tmpId`,`apId`):
            `setByParseId`[].add((move(`apId`.key), move(`apId`.val), "",
                                  clPositional))
          else:
            `setByParseId`[].add((move(`apId`.key), move(`apId`.val), msg,
                                  clBadVal))
        if not `prsOnlyId` and not argParse(`tmpId`, `tmpId`, `apId`):
            stderr.write `apId`.msg
            raise newException(ParseError, msg)
        `posId`.add(`tmpId`)))
    else:
      result.add(quote do:
        let msg = "Unexpected non-option " & $`pId`.key
        if cast[pointer](`setByParseId`) != cgSetByParseNil:
          `setByParseId`[].add((move(`apId`.key), move(`pId`.val), msg,
                                clNonOption))
        if not `prsOnlyId`:
          stderr.write(`cName`&" does not expect non-option arguments at \"" &
                       $`pId`.key & "\".\nRun with --help for full usage.\n")
          raise newException(ParseError, msg))

  let initVars=initVars0(); let optCases=optCases0(); let nonOpt=nonOpt0()
  let retType=fpars[0]
  let mrgNames = if mergeNames[1].len == 0: quote do: @[ `cName` ]  #default
                 else: mergeNames                                   #provided
  let docsVar = if   docs.kind == nnkAddr: docs[0]
                elif docs.kind == nnkCall: docs[1]
                else: newNimNode(nnkEmpty)
  let docsStmt = if docs.kind == nnkAddr or docs.kind == nnkCall:
                   quote do: `docsVar`.add(`cmtDoc`)
                 else: newNimNode(nnkEmpty)
  result = quote do:                                    #Overall Structure
    case `cf`.sigPIPE
    of spRaise: discard     # "Nim stdlib default"; Becoming raise in devel/1.6
    of spPass: SIGPIPE_pass()
    of spIsOk: SIGPIPE_isOk()
    if cast[pointer](`docs`) != cgVarSeqStrNil: `docsStmt`
    proc `disNm`(`cmdLineId`: seq[string] = mergeParams(`mrgNames`),
                 `usageId`=`usage`,`prefixId`="", `prsOnlyId`=false,
                 `skipHelp`=false, `noHdrId`=`noHdr`): `retType`=
      {.push hint[XDeclaredButNotUsed]: off.}
      `initVars`
      `aliases`
      var `keyCountId` {.used.} = initCountTable[string]()
      proc parser(args=`cmdLineId`, `provideId`=true) = #{.gcsafe.} clCfg access
        var `posNoId` = 0
        var `pId` = initOptParser(args, `apId`.shortNoVal, `apId`.longNoVal,
                                  `cf`.reqSep, `cf`.sepChars, `cf`.opChars,
                                  `stopWords`, `cf`.longPfxOk, `cf`.stopPfxOk)
        while true:
          next(`pId`)
          if `pId`.kind == cmdEnd: break
          if `pId`.kind == cmdError:
            if cast[pointer](`setByParseId`) != cgSetByParseNil:
              `setByParseId`[].add(("", "", move(`pId`.message), clParseOptErr))
            if not `prsOnlyId`:
              stderr.write(`pId`.message, "\n")
            break
          case `pId`.kind
            of cmdLongOption, cmdShortOption:
              `optCases`
            else:
              `nonOpt`
        `aliasesCallDfl`
      {.pop.}
      parser()
      if `mandId`.len > 0:
        if cast[pointer](`setByParseId`) != cgSetByParseNil:
          for m in `mandId`:
            `setByParseId`[].add((m, "", "Missing " & m, clMissing))
        if not `prsOnlyId`:
          stderr.write "Missing these " & `apId`.val4req & " parameters:\n"
          for m in `mandId`: stderr.write "  ", m, "\n"
          stderr.write "Run command with --help for more details.\n"
          raise newException(ParseError, "Missing one/some mandatory args")
      if `prsOnlyId` or (cast[pointer](`setByParseId`) != cgSetByParseNil and
          `setByParseId`[].numOfStatus(ClNoCall) > 0):
        return
      try: `callIt`
      except HelpError as e:
        stderr.write e.msg % ["HELP", `apId`.help]
        raise newException(ParseError, "Bad parameter user-syntax/semantics")
  when defined(printDispatch): echo repr(result)  # maybe print generated code

template discarder[T](a: T): void = # discard if possible, else identity;  Name
  when T is not void: discard a     #..ideas: discardVoid alwaysDiscard Discard
  else: a                           #..discarded maybeDiscard discardor..

template cligenQuit*(p: untyped, echoResult=false, noAutoEcho=false): auto =
  when echoResult:                            #CLI author requests echo
    try: echo p; quit(0)                      #May compile-time fail, but do..
    except HelpOnly, VersionOnly: quit(0)     #..want bubble up to CLI auth.
    except ParseError: quits(cgParseErrorExitCode)
  elif compiles(int(p)):                      #Can convert to int
    try: quits(int(p))
    except HelpOnly, VersionOnly: quit(0)
    except ParseError: quits(cgParseErrorExitCode)
  elif not noAutoEcho and compiles(echo p):   #autoEcho && have `$`
    try: echo p; quit(0)
    except HelpOnly, VersionOnly: quit(0)
    except ParseError: quits(cgParseErrorExitCode)
  else:                                       #void return type
    try: discarder(p); quit(0)
    except HelpOnly, VersionOnly: quit(0)
    except ParseError: quits(cgParseErrorExitCode)

template cligenHelp*(p: untyped, hlp: untyped, use: untyped, pfx: untyped,
                     skipHlp: untyped, noUHdr=false): auto =
  try: discarder(p(hlp, usage=use, prefix=pfx, skipHelp=skipHlp, noHdr=noUHdr))
  except HelpOnly: discard

macro cligenQuitAux*(cmdLine:seq[string], dispatchName: string, cmdName: string,
                     pro: untyped, echoResult: bool, noAutoEcho: bool,
                     mergeNames: seq[string] = @[]): untyped =
  let disNm = dispatchId(dispatchName.toString, cmdName.toString, repr(pro))
  let cName = if cmdName.toString.len == 0: $pro else: cmdName.toString
  let mergeNms = toStrSeq(mergeNames) & cName
  quote do: cligenQuit(`disNm`(mergeParams(`mergeNms`, `cmdLine`)),
                       `echoResult`, `noAutoEcho`)

template dispatchCf*(pro: typed{nkSym}, cmdName="", doc="", help: typed={},
 short:typed={},usage=clUse, cf:ClCfg=clCfg,echoResult=false,noAutoEcho=false,
 positional=AUTO, suppress:seq[string] = @[], implicitDefault:seq[string] = @[],
 dispatchName="", mergeNames: seq[string] = @[], alias: seq[ClAlias] = @[],
 stopWords:seq[string] = @[],noHdr=false,cmdLine=commandLineParams()): untyped =
  ## A convenience wrapper to both generate a command-line dispatcher and then
  ## call the dispatcher & exit; Params are same as the ``dispatchGen`` macro.
  dispatchGen(pro, cmdName, doc, help, short, usage, cf, echoResult, noAutoEcho,
              positional, suppress, implicitDefault, dispatchName, mergeNames,
              alias, stopWords, noHdr)
  cligenQuitAux(cmdLine, dispatchName, cmdName, pro, echoResult, noAutoEcho)

template dispatch*(pro: typed{nkSym}, cmdName="", doc="", help: typed={},
 short:typed={},usage=clUse,echoResult=false,noAutoEcho=false,positional=AUTO,
 suppress:seq[string] = @[], implicitDefault:seq[string] = @[], dispatchName="",
 mergeNames: seq[string] = @[], alias: seq[ClAlias] = @[],
 stopWords: seq[string] = @[], noHdr=false): untyped =
  ## Convenience `dispatchCf` wrapper to silence bogus GcUnsafe warnings at
  ## verbosity:2.  Parameters are the same as `dispatchCf` (except for no `cf`).
  proc cligenScope(cf: ClCfg) =
   dispatchCf(pro, cmdName, doc, help, short, usage, cf, echoResult, noAutoEcho,
              positional, suppress, implicitDefault, dispatchName, mergeNames,
              alias, stopWords, noHdr)
  cligenScope(clCfg)

proc subCmdName(p: NimNode): string =
  if p.paramPresent("cmdName"):     #CLI author-specified
    result = $p.paramVal("cmdName")
  else:                             #1st elt of bracket
    result = if p[0].kind == nnkDotExpr: $p[0][^1]  #qualified (1-level)
             else: $p[0]                            #unqualified

template unknownSubcommand*(cmd: string, subCmds: seq[string]) =
  let g0 = ha0("good"); let g1 = ha1("good"); let hlp = g0 & "help" & g1
  stderr.write "Unknown subcommand \"", ha0("bad"), cmd, ha1("bad"), "\".  "
  let sugg = suggestions(cmd, subCmds, subCmds)
  if sugg.len > 0:
    stderr.write "Maybe you meant one of:\n\t", g0, join(sugg, " "), g1, "\n\n"
  else:
    stderr.write "It is not similar to defined subcommands.\n\n"
  stderr.write "Run again with subcommand \"", hlp, "\" for detailed usage.\n"
  quits(cgParseErrorExitCode)

template ambigSubcommand*(cb: CritBitTree[string], attempt: string) =
  let g0 = ha0("good"); let g1 = ha1("good"); let hlp = g0 & "help" & g1
  stderr.write "Ambiguous subcommand \"", ha0("bad"), attempt, ha1("bad"), "\""
  stderr.write " matches:\n  ",g0,cb.valsWithPfx(attempt).join("\n  "),g1,"\n"
  stderr.write "Run with no-argument or \"", hlp, "\" for more details.\n"
  quits(cgParseErrorExitCode)

proc firstParagraph(doc: string): string =
  var first = true
  for line in doc.split('\n'):
    if line.len == 0: return
    result = result & (if first: "" else: " ") & line
    first = false

proc topLevelHelp*(doc: auto, use: auto, cmd: auto, subCmds: auto,
                   subDocs: auto): string =
  var pairs: seq[seq[string]]
  for i in 0 ..< subCmds.len:
    if clCfg.render != nil:
      pairs.add(@[subCmds[i], clCfg.render(subDocs[i].firstParagraph)])
    else:
      pairs.add(@[subCmds[i], subDocs[i].firstParagraph])
  let ifVsn = if clCfg.version.len > 0: "\nTop-level --version also available"
              else: ""
  let on = @[ clCfg.helpAttr.getOrDefault("cmd", ""),
              clCfg.helpAttr.getOrDefault("doc", "") ]
  let off= @[ clCfg.helpAttrOff.getOrDefault("cmd", ""),
              clCfg.helpAttrOff.getOrDefault("doc", "") ]
  let ww = wrapWidth(clCfg.widthEnv)
  let docUse = if clCfg.render != nil: wrap(clCfg.render(doc), ww)
               else: wrap(doc, ww)
  use % [ "doc", docUse, "command", on[0] & cmd & off[0], "ifVersion", ifVsn,
          "subcmds", addPrefix("  ", alignTable(pairs, 2, attrOn=on,
                                                attrOff=off, width=ww))]

proc docDefault(n: NimNode): NimNode =
  if   n.len > 1: newStrLitNode(summaryOfModule(n[1][0]))
  elif n.len > 0: newStrLitNode(summaryOfModule(n[0][0]))
  else: newStrLitNode("")

macro dispatchMultiGen*(procBkts: varargs[untyped]): untyped =
  ## Generate multi-cmd dispatch. ``procBkts`` are argLists for ``dispatchGen``.
  ## Eg., ``dispatchMultiGen([foo, short={"dryRun": "n"}], [bar, doc="Um"])``.
  let procBrackets = if procBkts.len < 2: procBkts[0] else: procBkts
  result = newStmtList()
  var prefix = "multi"
  if procBrackets[0][0].kind == nnkStrLit:
    prefix = procBrackets[0][0].strVal
  var cmd = srcBaseName(procBkts)
  var doc = newStrLitNode(""); var docChanged=false
  var use = quote do: (if clCfg.useMulti.len>0: clCfg.useMulti else: clUseMulti)
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
  let docId=ident("doc");let useId=ident("usage");let cmdId=ident("cmdName")
  for p in procBrackets:
    if p[0].kind == nnkStrLit:
      let main = procBrackets[0]
      for e in 1 ..< main.len:
        if main[e].kind == nnkExprEqExpr:
          if   main[e][0] == cmdId: cmd = main[e][1]
          elif main[e][0] == docId: doc = main[e][1]; docChanged = true
          elif main[e][0] == useId: use = main[e][1]
      continue
    let sCmdNm = p.subCmdName
    var c = newCall("dispatchGen")
    copyChildrenTo(p, c)
    if not c.paramPresent("mergeNames"):
      c.add(newParam("mergeNames", quote do: @[ `cmd`, `sCmdNm` ]))
    if not c.paramPresent("docs"):
      c.add(newParam("docs", quote do: `subDocsId`.addr))
    result.add(c)
    result.add(newCall("add", subCmdsId, newStrLitNode(sCmdNm)))
    result.add(newCall("incl",
                 subMchsId, newCall("optionNormalize", newStrLitNode(sCmdNm)),
                            newCall("helpCase", newStrLitNode(sCmdNm))))
  if not docChanged: doc = docDefault(procBrackets)
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
    let sCmdUsage  = if p.paramPresent("usage"): p.paramVal("usage")
                     else: ident("clUse")
    let mn = if p.paramPresent("mergeNames"): p.paramVal("mergeNames")
             else: quote do: @[ `cmd` ] #, `sCmdNm` ]
    cases.add(newNimNode(nnkOfBranch).
              add(newCall("optionNormalize", sCmdNm)).add(quote do:
      cligenQuitAux(`restId`, `disNm`, `sCmdNmS`, p[0], `sCmdEcR`.bool,
                    `sCmdNoAuEc`.bool, `mn`)))
    let spc = if cnt + 1 < len(procBrackets): quote do: echo ""
              else: newNimNode(nnkEmpty)
    helpDump.add(quote do:
      if `disNm` in `multiNmsId`:
        cligenHelp(`disNmId`,`helpSCmdId`,`sCmdUsage`,`prefixId`&"  ",true,true)
        `spc`
      else:
        cligenHelp(`disNmId`, `dashHelpId`, `sCmdUsage`, `prefixId`, true, true)
        `spc`)
  cases.add(newNimNode(nnkElse).add(quote do:
    if `arg0Id` == "":
      if `cmdLineId`.len > 0: ambigSubcommand(`subMchsId`, `cmdLineId`[0])
      else: echo topLevelHelp(`doc`, `use`,`cmd`,`subCmdsId`, `subDocsId`)
    elif `arg0Id` == "help":
      if ("dispatch" & `prefix`) in `multiNmsId` and `prefix` != "multi":
        echo ("  $1 $2 {SUBCMD} [subsubcommand-opts & args]\n" &
              "    where subsubcommand syntax is:") % [ `cmd`, `prefix` ]
      else:
        echo ("This is a multiple-dispatch command.  -h/--help/--help-syntax " &
              "is available\nfor top-level/all subcommands.  Usage is like:\n" &
              "    $1 {SUBCMD} [subcommand-opts & args]\n" &
              "where subcommand syntaxes are as follows:\n") % [ `cmd` ]
      let `dashHelpId` = @[ "--help" ]
      let `helpSCmdId` = @[ "help" ]
      `helpDump`
    else:
      unknownSubcommand(`arg0Id`, `subCmdsId`)))
  result.add(quote do:
    `multiNmsId`.add("dispatch" & `prefix`)
    proc `multiId`(`cmdLineId`: seq[string], `usageId`=clUse,`prefixId`="  ")=
      {.push hint[XDeclaredButNotUsed]: off.}
      let n = `cmdLineId`.len
      let `arg0Id`=if n>0: `subMchsId`.lengthen(`cmdLineId`[0], clCfg.stopPfxOk)
                   else: ""
      let `restId`: seq[string] = if n > 1: `cmdLineId`[1..<n] else: @[ ]
      `cases`)
  when defined(printDispatchMultiGen): echo repr(result)  # maybe print gen code

macro dispatchMultiDG*(procBkts: varargs[untyped]): untyped =
  let procBrackets = if procBkts.len < 2: procBkts[0] else: procBkts
  var prefix = "multi"
  let multiId = ident(prefix)
  let docId=ident("doc");let useId=ident("usage");let cmdId=ident("cmdName")
  result = newStmtList()
  result.add(newCall("dispatchGen", multiId))
  var doc = newStrLitNode(""); var docChanged=false
  var use = quote do: (if clCfg.useMulti.len>0: clCfg.useMulti else: clUseMulti)
  var cmd = srcBaseName(procBrackets)
  if procBrackets[0][0].kind == nnkStrLit:
    prefix = procBrackets[0][0].strVal
    let main = procBrackets[0]
    for e in 1 ..< main.len:
      if main[e].kind == nnkExprEqExpr:
        if   main[e][0] == cmdId: cmd = main[e][1]
        elif main[e][0] == docId: doc = main[e][1]; docChanged=true; continue
        elif main[e][0] == useId: use = main[e][1]; continue
      result[^1].add(main[e])
  if not docChanged: doc = docDefault(procBrackets)
  let subCmdsId = ident(prefix & "SubCmds")
  if not result[^1].paramPresent("stopWords"):
    result[^1].add(newParam("stopWords", subCmdsId))
  if not result[^1].paramPresent("noHdr"):
    result[^1].add(newParam("noHdr", newLit(true)))
  if not result[^1].paramPresent("dispatchName"):
    result[^1].add(newParam("dispatchName", newStrLitNode(prefix & "Subs")))
  if not result[^1].paramPresent("suppress"):
    result[^1].add(newParam("suppress", quote do: @[ "usage", "prefix" ]))
  let subDocsId = ident(prefix & "SubDocs")
  result[^1].add(newParam("usage", quote do:
    topLevelHelp(`doc`, `use`, `cmd`, `subCmdsId`, `subDocsId`)))
  when defined(printDispatchDG): echo repr(result)  # maybe print gen code

macro dispatchMulti*(procBrackets: varargs[untyped]): untyped =
  ## A wrapper to generate a multi-command dispatcher, call it, and quit.  The
  ## argument is a list of bracket expressions passed to ``dispatchGen`` for
  ## each subcommand.
  ##
  ## The VERY FIRST bracket can be the special string literal ``"multi"`` to
  ## adjust ``dispatchGen`` settings for the top-level proc that dispatches to
  ## subcommands.  In particular, top-level ``usage`` is a string template
  ## interpolating ``$command $doc $subcmds $ifVersion`` (``args`` & ``options``
  ## dropped and ``subcmd`` & ``ifVersion`` added relative to an ordinary
  ## ``dispatchGen`` usage template.).
  var prefix = "multi"
  if procBrackets[0][0].kind == nnkStrLit:
    prefix = procBrackets[0][0].strVal
  let subCmdsId = ident(prefix & "SubCmds")
  let subMchsId = ident(prefix & "SubMchs")
  let subsDispId = ident(prefix & "Subs")
  result = newStmtList()
  result.add(quote do: {.push warning[GCUnsafe]: off.})
  result.add(newCall("dispatchMultiGen", copyNimTree(procBrackets)))
  result.add(newCall("dispatchMultiDG", copyNimTree(procBrackets)))
  result.add(quote do:
    if true:
     {.push hint[GlobalVar]: off.}
     {.push warning[ProveField]: off.}
     let ps  = cast[seq[string]](mergeParams(@["multi"]))
     let ps0 = if ps.len>=1: `subMchsId`.lengthen(ps[0], clCfg.stopPfxOk)else:""
     let ps1 = if ps.len>=2: `subMchsId`.lengthen(ps[1], clCfg.stopPfxOk)else:""
     if ps.len>0 and ps0.len>0 and ps[0][0] != '-' and ps0 notin `subMchsId`:
       unknownSubcommand(ps[0], `subCmdsId`)
     elif ps.len > 0 and ps0.len == 0:
       ambigSubcommand(`subMchsId`, ps[0])
     elif ps.len == 2 and ps0 == "help":
       if ps1 in `subMchsId`: cligenQuit(`subsDispId`(@[ ps1, "--help" ]))
       elif ps1.len == 0: ambigSubcommand(`subMchsId`, ps[1])
       else: unknownSubcommand(ps[1], `subCmdsId`)
     else:
       cligenQuit(`subsDispId`())
     {.pop.}  #ProveField
     {.pop.}  #GlobalVar
    {.pop.}) #GCUnsafe
  when defined(printDispatchMulti): echo repr(result)  # maybe print gen code

macro initGen*(default: typed, T: untyped, positional="",
               suppress: seq[string] = @[], name=""): untyped =
  ##This macro generates an ``init`` proc for object|tuples of type ``T`` with
  ##param names equal to top-level field names & default values from ``default``
  ##like ``init(field1=default.field1,...): T = result.field1=field1; ..``,
  ##except if ``fieldN==positional fieldN: typeN`` is used instead which in turn
  ##makes ``dispatchGen`` bind that ``seq`` to catch positional CL args.
  var ti = default.getTypeImpl
  var indirect = 0
  case ti.typeKind:
  of ntyTuple: discard            #For tuples IdentDefs are top level
  of ntyObject: ti = ti[2]        #For objects, descend to the nnkRecList
  of ntyRef: ti = ti[0].getTypeImpl[2]; indirect = 1
  of ntyPtr: ti = ti[0].getTypeImpl[2]; indirect = 2
  else: error "default value is not a tuple or object"
  let empty = newNimNode(nnkEmpty)
  let suppressed = toIdSeq(suppress)
  let lastUnsuppressed = if suppress.len > 1 and suppress[1].len > 0 and
                           ($suppress[1][0]).startsWith "ALL AFTER ":
                             ident(($suppress[1][0])[10..^1]) else: nil
  let posId = ident(positional.strVal)
  var params = @[ quote do: `T` ] #Return type
  var assigns = newStmtList()     #List of assignments 
  if   indirect == 1: assigns.add(quote do: result.new)
  elif indirect == 2: assigns.add(quote do: result=cast[`T`](`T`.sizeof.alloc))
  for kid in ti.children:         #iterate over fields
    if kid.kind != nnkIdentDefs: warning "case objects unsupported"
    let id = ident(kid[0].strVal)
    if suppressed.has(id): continue
    params.add(if id == posId: newIdentDefs(id, kid[1], empty)
               else: newIdentDefs(id, empty, quote do: `default`.`id`))
    when (NimMajor,NimMinor,NimPatch) <= (0,20,0):  #XXX delete branch someday
      let argId = ident("arg"); let obId = ident("ob")
      let r = ident("result")
      let sid = ident($id & "setter"); let sidEq = ident($id & "setter=")
      assigns.add(quote do:
        proc `sidEq`(`obId`:var `T`, `argId` = `default`.`id`) = ob.`id`=`argId`
        `r`.`sid` = `id`)
    else:
      assigns.add(quote do: result.`id` = `id`)
    if id == lastUnsuppressed: break
  let nm = if name.strVal.len > 0: name.strVal else: "init"
  result = newProc(name = ident(nm), params = params, body = assigns)
  when defined(printInit): echo repr(result)  # maybe print gen code

template initFromCLcf*[T](default: T, cmdName: string="", doc: string="",
    help: typed={}, short: typed={}, usage: string=clUse, cf: ClCfg=clCfg,
    positional="", suppress: seq[string] = @[], mergeNames: seq[string] = @[],
    alias: seq[ClAlias] = @[]): T =
  ## Like ``dispatchCf`` but only ``quit`` when user gave bad CL, --help,
  ## or --version.  On success, returns ``T`` populated from object|tuple
  ## ``default`` and then from the ``mergeNames``/the command-line.  Top-level
  ## fields must have types with ``argParse`` & ``argHelp`` overloads.  Params
  ## to this common to ``dispatchGen`` mean the same thing.  The inability here
  ## to distinguish between syntactically explicit assigns & Nim type defaults
  ## eliminates several features and makes the `positional` default be empty.
  proc callIt(): T =
    initGen(default, T, positional, suppress, "ini")
    dispatchGen(ini, cmdName, doc, help, short, usage, cf, false, false, AUTO,
                @[], @[], "x", mergeNames, alias)
    try: result = x()
    except HelpOnly, VersionOnly: quit(0)
    except ParseError: quits(cgParseErrorExitCode)
  callIt()      #inside proc is not strictly necessary, but probably safer.

template initFromCL*[T](default: T, cmdName: string="", doc: string="",
    help: typed={}, short: typed={}, usage: string=clUse, positional="",
    suppress:seq[string] = @[], mergeNames:seq[string] = @[],
    alias: seq[ClAlias] = @[]): T =
  ## Convenience `initFromCLcf` wrapper to silence bogus GcUnsafe warnings at
  ## verbosity:2.  Parameters are as for `initFromCLcf` (except for no `cf`).
  proc cligenScope(cf: ClCfg): T =
    initFromCLcf(default, cmdName, doc, help, short, usage, cf, positional,
                 suppress, mergeNames, alias)
  cligenScope(clCfg)

macro initDispatchGen*(dispName, obName: untyped; default: typed; positional="";
                       suppress: seq[string] = @[]; body: untyped): untyped =
  ##Create a proc with signature from ``default`` that calls ``initGen`` and
  ##initializes ``var obName`` by calling to the generated initializer.  It puts
  ##``body`` inside an appropriate ``try/except`` so that you can just say:
  ##
  ## .. code-block:: nim
  ##   initDispatchGen(cmdProc, cfg, cfgDfl):
  ##     cfg.callAPI()
  ##     quit(min(127, cfg.nError))
  ##   dispatch(cmdProc)
  var ti = default.getTypeImpl
  case ti.typeKind:
  of ntyTuple: discard            #For tuples IdentDefs are top level
  of ntyObject: ti = ti[2]        #For objects, descend to the nnkRecList
  of ntyRef, ntyPtr: ti = ti[0].getTypeImpl[2]
  else: error "default value is not a tuple or object or ref|ptr to such"
  let suppressed = toIdSeq(suppress)
  let lastUnsuppressed = if suppress.len > 1 and suppress[1].len > 0 and
                           ($suppress[1][0]).startsWith "ALL AFTER ":
                             ident(($suppress[1][0])[10..^1]) else: nil
  let posId = ident(positional.strVal)
  let empty = newNimNode(nnkEmpty)
  var params = @[newEmptyNode()]  #initializers
  var call = newNimNode(nnkCall)  #call site
  call.add(ident("initter"))
  for kid in ti.children:         #iterate over fields
    if kid.kind != nnkIdentDefs: warning "case objects unsupported"
    let id = ident(kid[0].strVal)
    if suppressed.has(id): continue
    params.add(if id == posId: newIdentDefs(id, kid[1], empty)
               else: newIdentDefs(id, empty, quote do: `default`.`id`))
    call.add(quote do: `id`)
    if id == lastUnsuppressed: break
  let body = quote do:
    initGen(`default`, type(`default`), `positional`, `suppress`, "initter")
    try:
      var `obName` = `call`    #a, b, ..
      `body`
    except HelpOnly, VersionOnly: quit(0)
    except ParseError: quit(cgParseErrorExitCode)
  result = newProc(name = dispName, params = params, body = body)
  when defined(printIDGen): echo repr(result)  # maybe print gen code

proc mergeParams*(cmdNames: seq[string],
                  cmdLine=commandLineParams()): seq[string] =
  ##This is a pass-through parameter merge to provide a hook for CLI authors to
  ##create the ``seq[string]`` to be parsed from any run-time sources (likely
  ##based on ``cmdNames``) that they would like.  In a single ``dispatch``
  ##context, ``cmdNames[0]`` is the ``cmdName`` while in a ``dispatchMulti``
  ##context it is ``@[ <mainCommand>, <subCommand> ]``.
  cmdLine
