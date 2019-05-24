# This file is just for dispatch->dispatch2 backward compatibility.  The
# include pulling it in automatically will be removed after several cligen
# releases go by.  The file itself may stick around for a while after.
const helpTabOption*  = 0
const helpTabType*    = 1
const helpTabDefault* = 2
const helpTabDescrip* = 3
const helpTabColsDfl* = @[ helpTabOption, helpTabType,
                           helpTabDefault, helpTabDescrip ]

proc toHelpCols(x: seq[int]): seq[ClHelpCol] =
  for e in x: result.add(ClHelpCol(e))

type Version* = tuple[longOpt: string, output: string]

# UFCS is nice generally, but in this compatibility API case creates trouble
# since it is natural for the new name of the field to be the old name of the
# parameter, but this creates an identifier conflict.  So, we provide setters
# under distinct names for fields that are the same name as old params. I guess
# this is only for templates, which we need here to receive pro:typed{nkSym}:
#   https://github.com/nim-lang/Nim/issues/984
proc `vsnStr=`*(cf: var ClCfg, arg: string) = cf.version = arg
template `sepChar=`*(cf: var ClCfg, arg: untyped) = cf.sepChars = arg
template `opChar=`*(cf: var ClCfg, arg: untyped) = cf.opChars = arg

template dispatch2*(pro: typed{nkSym}, cmdName: string = "", doc: string = "",
 help: typed = {}, short: typed = {}, usage: string=clUse,
 prelude="Usage:\n  ", echoResult: bool=false, requireSeparator: bool=false,
 sepChars={'=',':'},
 opChars={'+','-','*','/','%','@',',','.','&','|','~','^','$','#','<','>','?'},
 helpTabColumnGap: int=2, helpTabMinLast: int=16, helpTabRowSep: string="",
 helpTabColumns = helpTabColsDfl, stopWords: seq[string] = @[],
 positional = AUTO, suppress: seq[string] = @[],
 shortHelp = 'h', implicitDefault: seq[string] = @[], mandatoryHelp="REQUIRED",
 mandatoryOverride: seq[string] = @[], version: Version=("",""),
 noAutoEcho: bool=false, dispatchName: string = "",
 mergeNames: seq[string] = @[]): untyped {.deprecated: "Use ClCfg-based `dispatch`".} =
 ##**Deprecated since cligen-0.9.28**: Use ``ClCfg``-based ``dispatch`` instead
 if shortHelp != 'h':
   stderr.write "cligen.dispatch2: shortHelp unsupported; use help[\"help\"].\n"
 if mandatoryOverride.len > 0:
   stderr.write "cligen.dispatch2: mandatoryOverride was removed\n"
 proc defineAndCall(cf: ClCfg) =
  var c = cf
  c.vsnStr      = version[1]
  c.reqSep      = requireSeparator
  c.sepChar     = sepChars
  c.hTabRowSep  = helpTabRowSep
  c.hTabColGap  = helpTabColumnGap
  c.hTabMinLast = helpTabMinLast
  c.hTabCols    = toHelpCols(helpTabColumns)
  c.hTabVal4req = mandatoryHelp
  c.opChar      = opChars
  dispatch(pro, cmdName, doc, help, short, prelude & usage, c, echoResult,
           noAutoEcho, positional, suppress, implicitDefault, dispatchName,
           mergeNames, stopWords)
 defineAndCall(clCfg)
