## ``argParse`` determines how string args are interpreted into native types.
## ``argHelp`` explains this interpretation to a command-line user.  Define new
## overloads in-scope of ``dispatch`` to override these or support more types.

from parseutils import parseBiggestInt, parseBiggestUInt, parseBiggestFloat
from strutils   import `%`, join, split, strip, toLowerAscii, cmpIgnoreStyle
from typetraits import `$`  # needed for $T
proc ERR*(x: string) = stderr.write(x)

proc nimEscape*(s: string): string =
  ## Until strutils gets a nimStringEscape that is not deprecated
  result = newStringOfCap(s.len + 2 + s.len shr 2)
  result.add('"')
  for c in s: result.addEscapedChar(c)
  result.add('"')

proc argKeys*(parNm: string, shrt: string, argSep="="): string =
  ## `argKeys` generates the option keys column in help tables
  result = if len(shrt) > 0: "-$1$3, --$2$3" % [ shrt, parNm, argSep ]
           else            : "--" & parNm & argSep

type argcvtParams* = object ## \
  ## Abstraction of non-param-type arguments to `argParse` and `argHelp`.
  ## Per-use data, then per-parameter data, then per-command/global data.
  key: string        ## key actually used for this option
  val: string        ## value actually given by user
  sep: string        ## separator actually used (including before '=' text)
  parName: string    ## long option key/parameter name
  parSh: char        ## short key for this option key
  parHelp: string    ## parameter help
  parDelimit: string ## parameter delimiting convention if a `seq`, `set`, etc.
  parReq: int        ## flag indicating parameter is mandatory
  count: int         ## count of times this parameter has been invoked
  Mand: string       ## how a mandatory defaults is rendered in help
  Help: string       ## the whole help string, for parse errors
  shortNoVal: ptr set[char]
  longNoVal: ptr seq[string]

proc argDf*(rq: int, dv: string): string =
  ## argDf is an argHelp space-saving template to decide what default col says.
  (if rq != 0: "REQUIRED" else: dv)

# bool
proc argParse*(dst: var bool, key: string, dfl: bool, val, help: string): bool =
  if len(val) > 0:
    case val.toLowerAscii   # Like `strutils.parseBool` but we also accept t&f
    of "t", "true", "yes", "y", "1", "on": dst = true
    of "f", "false", "no", "n",  "0", "off": dst = false
    else:
      ERR("Bool option \"$1\" non-boolean argument (\"$2\")\n$3"%[key,val,help])
      return false
  else:               # No option arg => reverse of default (usually, ..
    dst = not dfl     #.. but not always this means false->true)
  return true

proc argHelp*(dfl: bool; parNm, sh, parHelp: string, rq: int): seq[string] =
  result = @[ argKeys(parNm, sh, argSep=""), "bool", argDf(rq, $dfl), parHelp ]
#XXX move this logic to cligen?
# shortNoVal.incl(sh[0])            # bool can elide option arguments.
# longNoVal.add(parNm)              # So, add to *NoVal.

# string
proc argParse*(dst: var string; key, dfl, val, help: string): bool =
  if val == nil:
    ERR("Bad value nil for string param \"$1\"\n$2" % [ key, help ])
    return false
  dst = val
  return true

proc argHelp*(dfl: string; parNm, sh, parHelp: string, rq: int): seq[string] =
  result = @[ argKeys(parNm, sh), "string", argDf(rq, nimEscape(dfl)), parHelp ]

# cstring
proc argParse*(dst: var cstring, key:string, dfl:cstring, val,help:string):bool=
  if val == nil:
    ERR("Bad value nil for string param \"$1\"\n$2" % [ key, help ])
    return false
  dst = val
  return true

proc argHelp*(dfl: cstring; parNm, sh, parHelp: string, rq: int): seq[string] =
  result = @[ argKeys(parNm, sh), "string", argDf(rq, nimEscape($dfl)), parHelp ]

# char
proc argParse*(dst: var char, key: string, dfl: char, val, help: string): bool =
  if len(val) > 1:
    ERR("Bad value \"$1\" for single char param \"$2\"\n$3"%[ val, key, help ])
    return false
  dst = val[0]
  return true

proc argHelp*(dfl: char; parNm, sh, parHelp: string, rq: int): seq[string] =
  result = @[ argKeys(parNm, sh), "char", repr(dfl), parHelp ]

# enums
proc argParse*[T: enum](dst: var T, key: string, dfl: T, val,help: string):bool=
  var found = false
  for e in low(T)..high(T):
    if cmpIgnoreStyle(val, $e) == 0:
      dst = e
      found = true
      break
  if not found:
    var all = ""
    for e in low(T)..high(T): all.add($e & " ")
    all.add("\n\n")
    ERR("Bad enum value for option \"$1\". \"$2\" is not one of:\n  $3$4" %
        [ key, val, all, help ])
    return false
  return true

proc argHelp*[T: enum](dfl: T; parNm,sh,parHelp: string, rq: int): seq[string] =
  result = @[ argKeys(parNm, sh), "enum", $dfl, parHelp ]

# various numeric types
template argParseHelpNum(WideT: untyped, parse: untyped, T: untyped): untyped =
  proc argParse*(dst: var T, key: string, dfl: T; val, help: string): bool =
    var tmp: WideT
    if val == nil or parse(strip(val), tmp) != len(strip(val)):
      ERR("Bad value: \"$1\" for option \"$2\"; expecting $3\n$4" %
          [ (if val == nil: "nil" else: val), key, $T, help ])
      return false
    dst = T(tmp)
    return true
  proc argHelp*(dfl: T; parNm, sh, parHelp: string, rq: int): seq[string] =
    result = @[ argKeys(parNm, sh), $T, argDf(rq, $dfl), parHelp ]

argParseHelpNum(BiggestInt  , parseBiggestInt  , int    )  #ints
argParseHelpNum(BiggestInt  , parseBiggestInt  , int8   )
argParseHelpNum(BiggestInt  , parseBiggestInt  , int16  )
argParseHelpNum(BiggestInt  , parseBiggestInt  , int32  )
argParseHelpNum(BiggestInt  , parseBiggestInt  , int64  )
argParseHelpNum(BiggestUInt , parseBiggestUInt , uint   )  #uints
argParseHelpNum(BiggestUInt , parseBiggestUInt , uint8  )
argParseHelpNum(BiggestUInt , parseBiggestUInt , uint16 )
argParseHelpNum(BiggestUInt , parseBiggestUInt , uint32 )
argParseHelpNum(BiggestUInt , parseBiggestUInt , uint64 )
argParseHelpNum(BiggestFloat, parseBiggestFloat, float32)  #floats
argParseHelpNum(BiggestFloat, parseBiggestFloat, float  )
#argParseHelpNum(BiggestFloat, parseBiggestFloat, float64) #only a type alias

## **PARSING seq[T], set[T], .. FOR NON-OS-TOKENIZED OPTION VALUES**
##
## This module also defines argParse/argHelp pairs for ``seq[T]`` with flexible
## delimiting rules decided by the global var `delimit`.  A value of ``"<D>"``
## indicates delimiter-prefixed-values (DPSV) while a square-bracket character
## class like ``"[:,]"`` indicates a set of chars.  Anything else indicates
## that the whole string is the delimiter.  DPSV format looks like
## ``<DELIM-CHAR><COMPONENT><DELIM-CHAR><COMPONENT>..`` E.g., for CSV the user
## enters ``",Howdy,Neighbor"``.
##
## To allow easy appending to, removing from, and resetting existing sequence
## values, ``'+'``, ``'-'``, ``'='`` are recognized as special prefix chars.
## So, e.g., ``-o=,1,2,3 -o=+,4,5, -o=-3`` is equivalent to ``-o=,1,2,4,5``.
## Meanwhile, ``-o,1,2 -o:=-3 -o=++4`` makes ``o``'s value ``["-3", "+4"]``.
## It is not considered an error to try to delete a non-existent value.
##
## ``argParseHelpSeq(myType)`` will instantiate ``argParse`` and ``argHelp``
## for ``seq[myType]`` if you like any of the default delimiting schemes.
##
## The delimiting system is somewhat extensible.  If you have a new style or
## would like to override my usage messages then you can define your own
## ``argSeqSplitter`` and ``argSeqHelper`` anywhere before ``dispatchGen``.
## The optional ``+-=`` syntax will remain available.

var delimit = ","

proc argSeqSplitter*(sd: string, dst: var seq[string], src: string, o: int) =
  if sd == "<D>":                     # DELIMITER-PREFIXED Sep-Vals
    dst = src[o+1..^1].split(sd[0])   # E.g.: ",hello,world"
  else:
    dst = src[o..^1].split(sd)

proc argSeqHelper*(sd: string, Dfl: seq[string]; typ, dfl: var string) =
  if sd == "<D>":
    typ = "DPSV[" & typ & "]"
    dfl = if Dfl.len > 0: sd & Dfl.join(sd) else: "EMPTY"
  else:
    typ = sd & "SV[" & typ & "]"
    dfl = if Dfl.len > 0: Dfl.join(sd) else: "EMPTY"

## seqs
proc argParse*[T](dst: var seq[T], key: string, dfl: seq[T];
                 val, help: string): bool =
    if val == nil:
      ERR("Bad value nil for DSV param \"$1\"\n$2" % [ key, help ])
      return false
    type argSeqMode = enum Set, Append, Delete
    var mode = Set
    var origin = 0
    case val[0]
    of '+': mode = Append; inc(origin)
    of '-': mode = Delete; inc(origin)
    of '=': mode = Set; inc(origin)
    else: discard
    var tmp: seq[string]
    argSeqSplitter(delimit, tmp, $val, origin)
    case mode
    of Set:
      dst = @[ ]
      for e in tmp:
        var eParsed, eDefault: T
        if not argParse(eParsed, key, eDefault, e, help): return false
        dst.add(eParsed)
    of Append:
      if dst == nil: dst = @[ ]
      for e in tmp:
        var eParsed, eDefault: T
        if not argParse(eParsed, key, eDefault, e, help): return false
        dst.add(eParsed)
    of Delete:
      if dst == nil: dst = @[ ]
      var rqDel: seq[T] = @[ ]
      for e in tmp:
        var eParsed, eDefault: T
        if not argParse(eParsed, key, eDefault, e, help): return false
        rqDel.add(eParsed)
      for i, e in dst:
        if e in rqDel:
          dst.delete(i) #quadratic algo for many deletes, but preserves order
    return true

proc argHelp*[T](dfl: seq[T]; parNm, sh, parHelp: string; rq: int): seq[string]=
    var typ = $T; var df: string
    var dflSeq: seq[string] = @[ ]
    for d in dfl: dflSeq.add($d)
    argSeqHelper(delimit, dflSeq, typ, df)
    result = @[ argKeys(parNm, sh), typ, argDf(rq, df), parHelp ]

## sets
proc argParse*[T](dst: var set[T], key: string, dfl: set[T];
                 val, help: string): bool =
    if val == nil:
      ERR("Bad value nil for DSV param \"$1\"\n$2" % [ key, help ])
      return false
    type argSeqMode = enum Set, Append, Delete
    var mode = Set
    var origin = 0
    case val[0]
    of '+': mode = Append; inc(origin)
    of '-': mode = Delete; inc(origin)
    of '=': mode = Set; inc(origin)
    else: discard
    var tmp: seq[string]
    argSeqSplitter(delimit, tmp, $val, origin)
    case mode
    of Set:
      dst = {}
      for e in tmp:
        var eParsed, eDefault: T
        if not argParse(eParsed, key, eDefault, e, help): return false
        dst.incl(eParsed)
    of Append:
      for e in tmp:
        var eParsed, eDefault: T
        if not argParse(eParsed, key, eDefault, e, help): return false
        dst.incl(eParsed)
    of Delete:
      for e in tmp:
        var eParsed, eDefault: T
        if not argParse(eParsed, key, eDefault, e, help): return false
        dst.excl(eParsed)
    return true

proc argHelp*[T](dfl: set[T]; parNm, sh, parHelp: string; rq: int): seq[string]=
    var typ = $T; var df: string
    var dflSeq: seq[string] = @[ ]
    for d in dfl: dflSeq.add($d)
    argSeqHelper(delimit, dflSeq, typ, df)
    result = @[ argKeys(parNm, sh), typ, argDf(rq, df), parHelp ]
