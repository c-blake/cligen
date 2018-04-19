from parseutils import parseInt, parseFloat
from strutils   import `%`, join, split, wordWrap, repeat, escape, strip,
                       toLowerAscii
from terminal   import terminalWidth

proc postInc*(x: var int): int =
  ## Similar to post-fix `++` in C languages: yield initial val, then increment
  result = x
  inc(x)

proc keys*(parNm: string, shrt: string, argSep="="): string =
  result = if len(shrt) > 0: "-$1$3, --$2$3" % [ shrt, parNm, argSep ]
           else            : "--" & parNm & argSep

var REQUIRED* = "REQUIRED"  # CLI-author can change, if desired.

template argRq*(rq: int, dv: string): string =
  ## argRq is a simple space-saving template to decide the argHelp defVal column
  (if rq != 0:
    REQUIRED
  else:
    dv)

template argRet*(code: int, msg: string) =
  ## argRet is a simple space-saving template to write msg and return a code.
  stderr.write(msg)                         # if code==0 send to stdout?
  return code

proc addPrefix*(prefix: string, multiline=""): string =
  result = ""
  var lines = multiline.split("\n")
  if len(lines) > 1:
    for line in lines[0 .. ^2]:
      result &= prefix & line & "\n"
  if len(lines) > 0:
    if len(lines[^1]) > 0:
      result &= prefix & lines[^1] & "\n"

proc alignTable*(tab: seq[array[0..3, string]], prefixLen=0,
                 colGap=2, minLast=16, rowSep="", cols = @[0,1,2,3]): string =
  result = ""
  var wCol: array[0 .. 3, int]
  let last = cols[^1]
  for row in tab:
    for c in cols[0 .. ^2]: wCol[c] = max(wCol[c], row[c].len)
  var wTerm = terminalWidth() - prefixLen
  var leader = (cols.len - 1) * colGap
  for c in cols[0 .. ^2]: leader += wCol[c]
  wCol[last] = max(minLast, wTerm - leader)
  for row in tab:
    for c in cols[0 .. ^2]:
      result &= row[c] & repeat(" ", wCol[c] - row[c].len + colGap)
    var wrapped = wordWrap(row[last], maxLineWidth = wCol[last]).split("\n")
    result &= (if wrapped.len > 0: wrapped[0] else: "") & "\n"
    for j in 1 ..< len(wrapped):
      result &= repeat(" ", leader) & wrapped[j] & "\n"
    result &= rowSep

## argParse and argHelp are a pair of related overloaded template helpers for
## each supported Nim type of optional parameter.  You may define new ones for
## your own custom types as needed wherever convenient in-scope of dispatch().
## argParse determines how string arguments are interpreted into native types
## while argHelp explains this interpretation to a command-line user.

# bool
template argParse*(dst: bool, key: string, dfl: bool, val: string, help: string) =
  if len(val) > 0:
    var v = val.toLowerAscii
    if   v == "t" or v == "true" or v == "yes" or v == "y" or v == "1":
      dst = true
    elif v == "f" or v == "false" or v == "no" or v == "n" or v == "0":
      dst = false
    else:
      argRet(1, "Bool option \"$1\" non-boolean argument (\"$2\")\n$3" %
             [ key, val, help ])
  else:               # No option arg => reverse of default (usually, ..
    dst = not dfl     #.. but not always this means false->true)

template argHelp*(helpT: seq[array[0..3, string]], defVal: bool,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh, argSep=""),
              "toggle", argRq(rq, $defVal), parHelp ])
  shortNoVal.incl(sh[0])            # bool must elide option arguments.
  longNoVal.add(parNm)              # So, add to *NoVal.

# string
template argParse*(dst: string, key: string, dfl: string, val: string, help: string) =
  if val == nil:
    argRet(1, "Bad value nil for string param \"$1\"\n$2" % [ key, help ])
  dst = val

template argHelp*(helpT: seq[array[0..3, string]], defVal: string,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([keys(parNm, sh), "string", argRq(rq, escape(defVal)), parHelp])

# cstring
template argParse*(dst: cstring, key: string, dfl: cstring, val: string, help: string) =
  if val == nil:
    argRet(1, "Bad value nil for string param \"$1\"\n$2" % [ key, help ])
  dst = val

template argHelp*(helpT: seq[array[0..3, string]], defVal: cstring,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([keys(parNm, sh), "string", argRq(rq, escape($defVal)), parHelp])

# char
template argParse*(dst: char, key: string, dfl: char, val: string, help: string) =
  if val == nil or len(val) > 1:
    argRet(1, "Bad value nil/multi-char for char param \"$1\"\n$2" %
           [ key , help ])
  dst = val[0]

template argHelp*(helpT: seq[array[0..3, string]], defVal: char,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "char", repr(defVal), parHelp ])

# int
template argParse*(dst: int, key: string, dfl: int, val: string, help: string) =
  if val == nil or parseInt(strip(val), dst) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting int\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])

template argHelp*(helpT: seq[array[0..3, string]], defVal: int,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "int", argRq(rq, $defVal), parHelp ])

# int8
template argParse*(dst: int8, key: string, dfl: int8, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting int8\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = int8(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: int8,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "int8", argRq(rq, $defVal), parHelp ])

# int16
template argParse*(dst: int16, key: string, dfl: int16, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting int16\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = int16(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: int16,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "int16", argRq(rq, $defVal), parHelp ])

# int32
template argParse*(dst: int32, key: string, dfl: int32, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting int32\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = int32(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: int32,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "int32", argRq(rq, $defVal), parHelp ])

# int64
template argParse*(dst: int64, key: string, dfl: int64, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting int64\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = tmp

template argHelp*(helpT: seq[array[0..3, string]], defVal: int64,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "int64", argRq(rq, $defVal), parHelp ])

# uint
template argParse*(dst: uint, key: string, dfl: uint, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting uint\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = uint(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: uint,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "uint", argRq(rq, $defVal), parHelp ])

# uint8
template argParse*(dst: uint8, key: string, dfl: uint8, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting uint8\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = uint8(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: uint8,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "uint8", argRq(rq, $defVal), parHelp ])

# uint16
template argParse*(dst: uint16, key: string, dfl: uint16, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting uint16\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = uint16(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: uint16,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "uint16", argRq(rq, $defVal), parHelp ])

# uint32
template argParse*(dst: uint32, key: string, dfl: uint32, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting uint32\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = uint32(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: uint32,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "uint32", argRq(rq, $defVal), parHelp ])

# uint64
template argParse*(dst: uint64, key: string, dfl: uint64, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting uint64\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = uint64(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: uint64,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "uint64", argRq(rq, $defVal), parHelp ])

# float
template argParse*(dst: float, key: string, dfl: float, val: string, help: string) =
  if val == nil or parseFloat(strip(val), dst) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting float\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])

template argHelp*(helpT: seq[array[0..3, string]], defVal: float,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "float", argRq(rq, $defVal), parHelp ])

# float32
template argParse*(dst: float32, key: string, dfl: float32, val: string, help: string) =
  var tmp: float
  if val == nil or parseFloat(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting float32\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = float32(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: float32,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "float32", argRq(rq, $defVal), parHelp ])

# float64
template argParse*(dst: float64, key: string, dfl: float64, val: string, help: string) =
  if val == nil or parseFloat(strip(val), dst) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting float64\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])

template argHelp*(helpT: seq[array[0..3, string]], defVal: float64,
                  parNm: string, sh: string, parHelp: string, rq: int) =
  helpT.add([ keys(parNm, sh), "float64", argRq(rq, $defVal), parHelp ])
