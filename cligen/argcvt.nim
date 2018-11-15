## ``argParse`` determines how string args are interpreted into native types.
## ``argHelp`` explains this interpretation to a command-line user.  Define new
## overloads in-scope of ``dispatch`` to override these or support more types.

from parseutils import parseBiggestInt, parseBiggestUInt, parseBiggestFloat
from strutils   import `%`, join, split, strip, toLowerAscii, cmpIgnoreStyle
from typetraits import `$`  # needed for $T
proc ERR*(x: varargs[string, `$`]) = stderr.write(x)

proc nimEscape*(s: string): string =
  ## Until strutils gets a nimStringEscape that is not deprecated
  result = newStringOfCap(s.len + 2 + s.len shr 2)
  result.add('"')
  for c in s: result.addEscapedChar(c)
  result.add('"')

proc unescape*(s: string): string =
  ## Only handles \XX hex and ASCII right now
  let hexdigits = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
                    'a', 'b', 'c', 'd', 'e', 'f'}
  proc toHexDig(c: char): int =
    result = if c <= '9': ord(c) - ord('0') else: 10 + ord(c) - ord('a')
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    case s[i]:
    of '\\':
      if i + 3 >= s.len:
        raise newException(ValueError, "Incomplete 4-byte hex constant")
      if s[i+1].toLowerAscii != 'x':
        raise newException(ValueError, "hex constant not of form \xDD")
      let dhi = toLowerAscii(s[i+2])
      let dlo = toLowerAscii(s[i+3])
      if dhi notin hexdigits or dlo notin hexdigits:
        raise newException(ValueError, "non-hexadecimal constant: " & s[i..i+3])
      result.add(char(toHexDig(dhi)*16 + toHexDig(dlo)))
      inc(i, 4)
    else:
      result.add(s[i])
      inc(i, 1)

type ArgcvtParams* = object ## \
  ## Abstraction of non-param-type arguments to `argParse` and `argHelp`.
  ## Per-use data, then per-parameter data, then per-command/global data.
  key*: string        ## key actually used for this option
  val*: string        ## value actually given by user
  sep*: string        ## separator actually used (including before '=' text)
  parNm*: string      ## long option key/parameter name
  parSh*: string      ## short key for this option key
  parCount*: int      ## count of times this parameter has been invoked
  parReq*: int        ## flag indicating parameter is mandatory
  mand*: string       ## how a mandatory defaults is rendered in help
  help*: string       ## the whole help string, for parse errors
  delimit*: string    ## delimiting convention for `seq`, `set`, etc.
  shortNoVal*: set[char]  ## short options keys where value may be omitted
  longNoVal*: seq[string] ## long option keys where value may be omitted

proc argKeys*(a: ArgcvtParams, argSep="="): string =
  ## `argKeys` generates the option keys column in help tables
  result = if a.parSh.len > 0: "-$1$3, --$2$3" % [ a.parSh, a.parNm, argSep ]
           else              : "--" & a.parNm & argSep

proc argDf*(a: ArgcvtParams, dv: string): string =
  ## argDf is an argHelp space-saving utility proc to decide default column.
  (if a.parReq != 0: a.mand else: dv)

# bools
proc argParse*(dst: var bool, dfl: bool, a: var ArgcvtParams): bool =
  if len(a.val) > 0:
    case a.val.toLowerAscii  # Like `strutils.parseBool` but we also accept t&f
    of "t", "true" , "yes", "y", "1", "on" : dst = true
    of "f", "false", "no" , "n", "0", "off": dst = false
    else:
      ERR("Bool option \"$1\" non-boolean argument (\"$2\")\n$3" %
          [ a.key, a.val, a.help ])
      return false
  else:               # No option arg => reverse of default (usually, ..
    dst = not dfl     #.. but not always this means false->true)
  return true

proc argHelp*(dfl: bool; a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys(argSep=""), "bool", a.argDf($dfl) ]
  if a.parSh.len > 0:
    a.shortNoVal.incl(a.parSh[0]) # bool can elide option arguments.
  a.longNoVal.add(a.parNm)        # So, add to *NoVal.

# strings
proc argParse*(dst: var string, dfl: string, a: var ArgcvtParams): bool =
  if a.sep.len > 0:                   # no separator => assignment
    case a.sep[0]                     # char on command line before [=:]
    of '+', '&': dst.add(a.val)       # Append Mode
    of '^': dst = a.val & dst         # Prepend Mode
    else: dst = a.val                 # Assign Mode
  else: dst = a.val                   # No Operator => Assign Mode
  return true

proc argHelp*(dfl: string; a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys, "string", a.argDf(nimEscape(dfl)) ]

# cstrings
proc argParse*(dst: var cstring, dfl: cstring, a: var ArgcvtParams): bool =
  dst = a.val
  return true

proc argHelp*(dfl: cstring; a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys, "string", a.argDf(nimEscape($dfl)) ]

# chars
proc argParse*(dst: var char, dfl: char, a: var ArgcvtParams): bool =
  let val = unescape(a.val)
  if len(val) != 1:
    ERR("Bad value \"$1\" for single char param \"$2\"\n$3" %
        [ a.val, a.key, a.help ])
    return false
  dst = val[0]
  return true

proc argHelp*(dfl: char; a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys, "char", a.argDf(repr(dfl)) ]

# enums
proc argParse*[T: enum](dst: var T, dfl: T, a: var ArgcvtParams): bool =
  var found = false
  if a.val.len > 0:
    for e in low(T)..high(T):
      if cmpIgnoreStyle(a.val, $e) == 0:
        dst = e
        found = true
        break
  if not found:
    var all = ""
    for e in low(T)..high(T): all.add($e & " ")
    all.add("\n\n")
    ERR("Bad enum value for option \"$1\". \"$2\" is not one of:\n  $3$4" %
        [ a.key, a.val, all, a.help ])
    return false
  return true

proc argHelp*[T: enum](dfl: T; a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys, "enum", $dfl ]

# various numeric types
proc low *[T: uint|uint64](x: typedesc[T]): T = cast[T](0)  #Missing in stdlib
proc high*[T: uint|uint64](x: typedesc[T]): T = cast[T](-1) #Missing in stdlib

template argParseHelpNum*(WideT: untyped, parse: untyped, T: untyped): untyped =
  proc argParse*(dst: var T, dfl: T, a: var ArgcvtParams): bool =
    var parsed: WideT
    let stripped = strip(a.val)
    if len(stripped) == 0 or parse(stripped, parsed) != len(stripped):
      ERR("Bad value: \"$1\" for option \"$2\"; expecting $3\n$4" %
          [ a.val, a.key, $T, a.help ])
      return false
    if parsed < WideT(T.low) or parsed > WideT(T.high):
      ERR("Bad value: \"$1\" for option \"$2\"; out of range for $3\n$4" %
          [ a.val, a.key, $T, a.help ])
      return false
    dst = T(parsed)
    return true

  proc argHelp*(dfl: T, a: var ArgcvtParams): seq[string] =
    result = @[ a.argKeys, $T, a.argDf($dfl) ]

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

## **PARSING AGGREGATES (string,set,seq,..) FOR NON-OS-TOKENIZED OPTION VALS**
##
## This module also defines ``argParse``/``argHelp`` pairs for ``seq[T]`` with
## delimiting rules decided by ``delimit`` (set via ``dispatch(..delimit=)``).
## A value of ``"<D>"`` indicates delimiter-prefixed-values (DPSV) while a
## square-bracket character class like ``"[:,]"`` indicates a set of chars and
## anything else indicates that the whole string is the delimiter.
##
## DPSV format looks like ``<DELIMCHAR><ELEMENT><DELIMCHAR><ELEMENT>..``
## E.g., for CSV the user enters ``",foo,bar"``.
##
## The delimiting system is somewhat extensible.  If you have a new style or
## would like to override defaults then you can define your own ``argAggSplit``
## and ``argAggHelp`` anywhere before ``dispatchGen``.
##
## To allow easy incremental modifications to existing values, a few ``opChars``
## are interpreted by various ``argParse``.  For ``string`` and ``seq[T]``,
## ``'+'`` (or ``'&'``) and ``'^'`` mean append and prepend.  For ``set[T]``
## and ``seq[T]`` there is also ``'-'`` for deletion (of all matches).  E.g.,
## ``-o=,1,2,3 -o+=,4,5, -o^=,0 -o=-3`` is equivalent to ``-o=,0,1,2,4,5``.
## It is not considered an error to try to delete a non-existent value.
##
## When no operator is provided by the user (i.e. styles like ``-o,x,y,z -o
## ,a,b --opt ,c,d``), append/incl mode is used for ``seq`` and ``set`` (but
## not ``string`` which assigns by default).  Note that users are always free
## to simply provide an ``'='`` to signify assignment mode instead.

proc argAggSplit*[T](src: string, delim: string, a: var ArgcvtParams): seq[T] =
  var toks: seq[string]
  if delim == "<D>":                      # DELIMITER-PREFIXED Sep-Vals
    toks = src[1..^1].split(delim[0])     # E.g.: ",hello,world"
  elif delim[0] == '[' and delim[^1] == ']':
    var cclass: set[char] = {}            # is there no toSet?
    for c in delim[1..^2]: cclass.incl(c)
    toks = src.split(cclass)
  else:
    toks = src.split(delim)
  var parsed, default: T
  result = @[]
  for tok in toks:
    a.val = tok
    if not argParse(parsed, default, a):
      result.setLen(0)
      return
    result.add(parsed)

proc argAggHelp*(sd: string, dfls: seq[string]; typ, dfl: var string) =
  if sd == "<D>":
    typ = "DPSV[" & typ & "]"
    dfl = if dfls.len > 0: sd & dfls.join(sd) else: "EMPTY"
  else:
    typ = (if sd=="\t": "T" else: sd) & "SV[" & typ & "]"
    dfl = if dfls.len > 0: dfls.join(if sd=="\t": "\\t" else: sd) else: "EMPTY"

# sets
proc incl*[T](dst: var set[T], toIncl: openArray[T]) =
  ## incl from an openArray; How can this NOT be in the stdlib?
  for e in toIncl: dst.incl(e)
proc excl*[T](dst: var set[T], toExcl: openArray[T]) =
  ## excl from an openArray; How can this NOT be in the stdlib?
  for e in toExcl: dst.excl(e)

proc argParse*[T](dst: var set[T], dfl: set[T], a: var ArgcvtParams): bool =
  let parsed = argAggSplit[T](a.val, a.delimit, a)
  if parsed.len == 0: return false
  if a.sep.len > 0:
    case a.sep[0]                     # char on command line before [=:]
    of '+', '&': dst.incl(parsed)     # Incl Mode
    of '-': dst.excl(parsed)          # Excl Mode
    else: dst = {}; dst.incl(parsed)  # Assign Mode
  else: dst.incl(parsed)              # No Operator => Incl Mode
  return true

proc argHelp*[T](dfl: set[T], a: var ArgcvtParams): seq[string]=
  var typ = $T; var df: string
  var dflSeq: seq[string] = @[ ]
  for d in dfl: dflSeq.add($d)
  argAggHelp(a.delimit, dflSeq, typ, df)
  result = @[ a.argKeys, typ, a.argDf(df) ]

# seqs
proc argParse*[T](dst: var seq[T], dfl: seq[T], a: var ArgcvtParams): bool =
  let parsed = argAggSplit[T](a.val, a.delimit, a)
  if parsed.len == 0: return false
  if a.sep.len > 0:
    case a.sep[0]                     # char on command line before [=:]
    of '+', '&': dst.add(parsed)      # Append Mode
    of '^': dst = parsed & dst        # Prepend Mode
    of '-':                           # Delete mode
      for i, e in dst:
        if e in parsed: dst.delete(i) # Quadratic algo, but preserves order
    else: dst = parsed                # Assign Mode
  else: dst.add(parsed)               # No Operator => Append Mode
  return true

proc argHelp*[T](dfl: seq[T], a: var ArgcvtParams): seq[string]=
  var typ = $T; var df: string
  var dflSeq: seq[string] = @[ ]
  for d in dfl: dflSeq.add($d)
  argAggHelp(a.delimit, dflSeq, typ, df)
  result = @[ a.argKeys, typ, a.argDf(df) ]

import sets # HashSets

proc argParse*[T](dst: var HashSet[T], dfl: HashSet[T],
                  a: var ArgcvtParams): bool =
  if a.val.len == 0:
    ERR("Empty value for DSV param \"$1\"\n$2" % [ a.key, a.help ])
    return false
  let parsed = toSet(argAggSplit[T](a.val, a.delimit, a))
  if card(parsed) == 0: return false
  if a.sep.len > 0:
    case a.sep[0]                       # char on command line before [=:]
    of '+', '&': dst.incl(parsed)       # Incl Mode
    of '-': dst.excl(parsed)            # Excl Mode
    else: dst.clear(); dst.incl(parsed) # Assign Mode
  else: dst.incl(parsed)                # No Operator => Incl Mode
  return true

proc argHelp*[T](dfl: HashSet[T], a: var ArgcvtParams): seq[string]=
  var typ = $T; var df: string
  var dflSeq: seq[string] = @[ ]
  for d in dfl: dflSeq.add($d)
  argAggHelp(a.delimit, dflSeq, typ, df)
  result = @[ a.argKeys, typ, a.argDf(df) ]

#import tables # Tables XXX need 2D delimiting convention
#? intsets, lists, deques, queues, etc?
