## ``argParse`` and ``argHelp`` are a pair of related overloaded template
## helpers for each supported Nim type of optional parameter.  ``argParse``
## determines how string arguments are interpreted into native types while
## ``argHelp`` explains this interpretation to a command-line user.  You may
## define new ones for your own custom types as needed wherever convenient
## in-scope of ``dispatch``.

from parseutils import parseBiggestInt, parseBiggestUInt, parseBiggestFloat
from strutils   import `%`, join, split, wordWrap, repeat, strip, toLowerAscii
from textUt     import TextTab
from typetraits import `$`

proc nimEscape*(s: string): string =
  ## Until strutils gets a nimStringEscape that is not deprecated
  result = newStringOfCap(s.len + 2 + s.len shr 2)
  result.add('"')
  for c in s: result.addEscapedChar(c)
  result.add('"')

proc keys*(parNm: string, shrt: string, argSep="="): string =
  ## keys(parNm, shrt, argSep) generates the option keys column in help tables
  result = if len(shrt) > 0: "-$1$3, --$2$3" % [ shrt, parNm, argSep ]
           else            : "--" & parNm & argSep

var REQUIRED* = "REQUIRED"  # CLI-author can change, if desired.

template argRq*(rq: int, dv: string): string =
  ## argRq is an argHelp space-saving template to decide what default col says.
  (if rq != 0:
    REQUIRED
  else:
    dv)

template argRet*(code: int, msg: string) =
  ## argRet is an argParse space-saving template to write msg & return a code.
  stderr.write(msg)                         # if code==0 send to stdout?
  return code

# bool
template argParse*(dst: bool, key: string, dfl: bool, val, help: string) =
  if len(val) > 0:
    case val.toLowerAscii   # Like `strutils.parseBool` but we also accept t&f
    of "t", "true", "yes", "y", "1", "on": dst = true
    of "f", "false", "no", "n",  "0", "off": dst = false
    else:
      argRet(1, "Bool option \"$1\" non-boolean argument (\"$2\")\n$3" %
             [ key, val, help ])
  else:               # No option arg => reverse of default (usually, ..
    dst = not dfl     #.. but not always this means false->true)

template argHelp*(ht: TextTab, dfl: bool; parNm, sh, parHelp: string, rq: int) =
  ht.add(@[ keys(parNm, sh, argSep=""), "bool", argRq(rq, $dfl), parHelp ])
  shortNoVal.incl(sh[0])            # bool must elide option arguments.
  longNoVal.add(parNm)              # So, add to *NoVal.

# string
template argParse*(dst: string, key: string, dfl: string, val, help: string) =
  if val == nil:
    argRet(1, "Bad value nil for string param \"$1\"\n$2" % [ key, help ])
  dst = val

template argHelp*(ht: TextTab, dfl: string; parNm, sh, parHelp: string, rq:int)=
  ht.add(@[keys(parNm, sh), "string", argRq(rq, nimEscape(dfl)), parHelp])

# cstring
template argParse*(dst: cstring, key: string, dfl: cstring, val, help: string) =
  if val == nil:
    argRet(1, "Bad value nil for string param \"$1\"\n$2" % [ key, help ])
  dst = val

template argHelp*(ht: TextTab, dfl: cstring; parNm, sh, parHelp: string,rq:int)=
  ht.add(@[keys(parNm, sh), "string", argRq(rq, nimEscape($dfl)), parHelp])

# char
template argParse*(dst: char, key: string, dfl: char, val, help: string) =
  if val == nil or len(val) > 1:
    argRet(1, "Bad value nil/multi-char for char param \"$1\"\n$2" %
           [ key , help ])
  dst = val[0]

template argHelp*(ht: TextTab, dfl: char; parNm, sh, parHelp: string, rq: int) =
  ht.add(@[ keys(parNm, sh), "char", repr(dfl), parHelp ])

# enums
template argParse*[T: enum](dst: T, key: string, dfl: T, val, help: string) =
  block:
    var found = false
    for e in low(T)..high(T):
      if cmpIgnoreStyle(val, $e) == 0:
        dst = e
        found = true
        break
    if not found:
      var allEnums = ""
      for e in low(T)..high(T): allEnums.add($e & " ")
      allEnums.add("\n")
      argRet(1, "Bad enum value for option \"$1\". Not in set:\n  $2\n$3" % [
             key, allEnums, help ])

template argHelp*[T: enum](ht: TextTab, dfl: T; parNm, sh, parHelp: string, rq: int) =
  ht.add(@[ keys(parNm, sh), "enum", $dfl, parHelp ])

# various numeric types
template argParseHelpNum(WideT: untyped, parse: untyped, T: untyped): untyped =

  template argParse*(dst: T, key: string, dfl: T, val: string, help: string) =
    block: # {.inject.} needed to get tmp typed, but block: prevents it leaking
      var tmp {.inject.}: WideT
      if val == nil or parse(strip(val), tmp) != len(strip(val)):
        argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting $3\n$4" %
               [ (if val == nil: "nil" else: val), key, $T, help ])
      else: dst = T(tmp)

  template argHelp*(ht: TextTab, dfl: T; parNm, sh, parHelp: string, rq: int) =
    ht.add(@[ keys(parNm, sh), $T, argRq(rq, $dfl), parHelp ])

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

## **PARSING ``seq[T]`` FOR NON-OS-TOKENIZED OPTION VALUES**
##
## This module also defines argParse/argHelp pairs for ``seq[T]`` with flexible
## delimiting rules determined by a **necessary binding of ``seqDelimit`` in the
## scope of ``dispatchGen``**.  You will get a compile-time error if you have
## ``seq[T]`` parameters in wrapped ``proc`` and do not assign ``seqDelimit``.
##
## ``let seqDelimit = { ',', ':' }`` or ``let seqDelimit = "@"`` or ``let
## seqDelimit = '%'`` all work.
##
## A less-common-than-it-should-be rule is activated by ``seqDelimit="<D>"``.
## This is what I call delimiter-prefixed-separated-value (DPSV) format:
##   ``<DELIM-CHAR><COMPONENT><DELIM-CHAR><COMPONENT>..``
## E.g., for CSV the user enters ``",Howdy,Neighbor"``.  At the cost of one
## extra character, users can choose delimiters that do not conflict with
## body text on a case-by-case basis which makes quoting rules unneeded.
##
## To allow easy appending to, removing from, and resetting existing sequence
## values, ``'+'``, ``'-'``, ``'='`` are recognized as special prefix chars.
## So, e.g., ``-o=,1,2,3 -o=+,4,5, -o=-3`` is equivalent to ``-o=,1,2,4,5``.
## Meanwhile, ``-o,1,2 -o:=-3 -o=++4`` makes ``o``'s value ``["-3", "+4"]``.
## It is not considered an error to try to delete a non-existent value.

## ``argParseHelpSeq(myType)`` will instantiate ``argParse`` and ``argHelp``
## for ``seq[myType]`` if you like any of the default delimiting schemes.
##
## The delimiting system is somewhat extensible.  If you have a new style or
## would like to override my usage messages then you can define your own
## ``argSeqSplitter`` and ``argSeqHelper`` anywhere before ``dispatchGen``.
## The optional ``+-=`` syntax will remain available.

template argSeqSplitter*(sd: char, dst: seq[string], src: string, o: int) =
  dst = src[o..^1].split(sd)

template argSeqSplitter*(sd: set[char], dst: seq[string], src: string, o: int) =
  dst = src[o..^1].split(sd)

template argSeqSplitter*(sd: string, dst: seq[string], src: string, o: int) =
  if sd == "<D>":                     # DELIMITER-PREFIXED Sep-Vals
    dst = src[o+1..^1].split(sd[0])   # E.g.: ",hello,world"
  else:
    dst = src[o..^1].split(sd)

template argSeqHelper*(sd: char, Dfl: seq[string]; typ, dfl: string) =
  let dlm = $sd
  typ = dlm & "SV[" & typ & "]"
  dfl = if Dfl.len > 0: Dfl.join(dlm) else: "EMPTY"

proc charClass*(s: set[char]): string =
  result = "["
  for c in s: result.add(c)
  result.add("]")

template argSeqHelper*(sd: set[char], Dfl: seq[string]; typ, dfl: string) =
  let dlm = charClass(sd)
  typ = dlm & "SV[" & typ & "]"
  dfl = if Dfl.len > 0: Dfl.join(dlm) else: "EMPTY"

template argSeqHelper*(sd: string, Dfl: seq[string]; typ, dfl: string) =
  if sd == "<D>":
    typ = "DPSV[" & typ & "]"
    dfl = if Dfl.len > 0: sd & Dfl.join(sd) else: "EMPTY"
  else:
    typ = sd & "SV[" & typ & "]"
    dfl = if Dfl.len > 0: Dfl.join(sd) else: "EMPTY"

template argParseHelpSeq*(T: untyped): untyped =
  template argParse*(dst: seq[T], key: string, dfl: seq[T], val, help: string)
    {.dirty.} =  # w/o get un/ambiguous typed 'mode'
    if val == nil:
      argRet(1, "Bad value nil for DSV param \"$1\"\n$2" % [ key, help ])
    block:
      type argSeqMode = enum Set, Append, Delete
      var mode = Set
      var origin = 0
      case val[0]
      of '+': mode = Append; inc(origin)
      of '-': mode = Delete; inc(origin)
      of '=': mode = Set; inc(origin)
      else: discard
      var tmp: seq[string]
      argSeqSplitter(seqDelimit, tmp, $val, origin)
      case mode
      of Set:
        dst = @[ ]
        for e in tmp:
          var eParsed, eDefault: T
          argParse(eParsed, key, eDefault, e, help)
          dst.add(eParsed)
      of Append:
        if dst == nil: dst = @[ ]
        for e in tmp:
          var eParsed, eDefault: T
          argParse(eParsed, key, eDefault, e, help)
          dst.add(eParsed)
      of Delete:
        if dst == nil: dst = @[ ]
        var rqDel: seq[T] = @[ ]
        for e in tmp:
          var eParsed, eDefault: T
          argParse(eParsed, key, eDefault, e, help)
          rqDel.add(eParsed)
        for i, e in dst:
          if e in rqDel:
            dst.delete(i) #quadratic algo for many deletes, but preserves order

  template argHelp*(ht: TextTab; dfl: seq[T]; parNm, sh, parHelp: string;
                    rq: int) {.dirty.} = # w/o get un/ambiguous typed 'dflSeq'
    when not declared(seqDelimit):
      {.fatal: "Define seqDelimit to {some char|seq[char]|string|\"<D>\"}".}
    block:
      var typ = $T; var df: string
      var dflSeq: seq[string] = @[ ]
      for d in dfl: dflSeq.add($d)
      argSeqHelper(seqDelimit, dflSeq, typ, df)
      ht.add(@[ keys(parNm, sh), typ, argRq(rq, df), parHelp ])

argParseHelpSeq(bool   )
argParseHelpSeq(string )
argParseHelpSeq(cstring)
argParseHelpSeq(char   )
argParseHelpSeq(int    )  #ints
argParseHelpSeq(int8   )
argParseHelpSeq(int16  )
argParseHelpSeq(int32  )
argParseHelpSeq(int64  )
argParseHelpSeq(uint   )  #uints
argParseHelpSeq(uint8  )
argParseHelpSeq(uint16 )
argParseHelpSeq(uint32 )
argParseHelpSeq(uint64 )
argParseHelpSeq(float32)  #floats
argParseHelpSeq(float)
#argParseHelpSeq(float64) #only a type alias
#argParseHelpSeq(enum T) #XXX Fails; Natural re-impl arg(Parse|Help)*[T: enum]
                         #XXX gets internal error: getInt. Unsupported for now.
