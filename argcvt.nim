from parseutils import parseInt, parseFloat
from strutils   import `%`, join, split, wordWrap, repeat, escape
from terminal   import terminalWidth

proc postInc*(x: var int): int =
  ## Similar to post-fix `++` in C languages: yield initial val, then increment
  result = x
  inc(x)

proc keys*(parNm: string, shrt: string): string =
  result = if len(shrt) > 0: "--$1=, -$2=" % [ parNm, shrt ]
           else            : "--" & parNm & "="

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

proc alignTable*(tab: seq[array[0..3, string]],
                 prefixLen=0, colGap=2, min4th=16, rowSep=""): string =
  result = ""
  var wCol: array[0 .. 3, int]
  for row in tab:
    for c in 0 .. 2: wCol[c] = max(wCol[c], row[c].len)
  var wTerm = terminalWidth() - prefixLen
  var leader = wCol[0] + wCol[1] + wCol[2] + 3 * colGap
  wCol[3] = max(min4th, wTerm - leader)
  for row in tab:
    for c in 0 .. 2:
      result &= row[c] & repeat(" ", wCol[c] - row[c].len + colGap)
    var wrapped = wordWrap(row[3], maxLineWidth = wCol[3]).split("\n")
    result &= wrapped[0] & "\n"
    for j in 1 ..< len(wrapped):
      result &= repeat(" ", leader) & wrapped[j] & "\n"
    result &= rowSep

## argParse and argHelp are a pair of related overloaded template helpers for
## each supported Nim type of optional parameter.  You may define new ones for
## your own custom types as needed wherever convenient in-scope of dispatch().
## argParse determines how string arguments are interpreted into native types
## while argHelp explains this interpretation to a command-line user.

# bool
template argParse*(dst: bool, key: string, val: string, help: string) =
  if len(val) > 0:
    argRet(1, "Bool option \"$1\" not expecting argument (\"$2\")\n$3" %
           [ key, val, help ])
  dst = not dst

template argHelp*(helpT: seq[array[0..3, string]], defVal: bool,
                  parNm: string, sh: string, parHelp: string) =
  let keys = if len(sh) > 0: "--$1, -$2" % [ parNm, sh ] # bools take no arg
             else          : "--" & parNm
  helpT.add([ keys, "toggle", $defVal, parHelp ])
  shortBool.add(sh)                 # only bools can elide option arguments..
  longBool.add(parNm)               #..and so only those should add to *Bool.

# string
template argParse*(dst: string, key: string, val: string, help: string) =
  if val == nil:
    argRet(1, "Bad value nil for string param \"$1\"\n$2" % [ key, help ])
  dst = val

template argHelp*(helpT: seq[array[0..3, string]], defVal: string,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([keys(parNm, sh), "string", escape(defVal), parHelp])

# cstring
template argParse*(dst: cstring, key: string, val: string, help: string) =
  if val == nil:
    argRet(1, "Bad value nil for string param \"$1\"\n$2" % [ key, help ])
  dst = val

template argHelp*(helpT: seq[array[0..3, string]], defVal: cstring,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([keys(parNm, sh), "string", escape($defVal), parHelp])

# char
template argParse*(dst: char, key: string, val: string, help: string) =
  if val == nil or len(val) > 1:
    argRet(1, "Bad value nil/multi-char for char param \"$1\"\n$2" %
           [ key , help ])
  dst = val[0]

template argHelp*(helpT: seq[array[0..3, string]], defVal: char,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "char", repr(defVal), parHelp ])

# int
template argParse*(dst: int, key: string, val: string, help: string) =
  if val == nil or parseInt(strip(val), dst) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting int\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])

template argHelp*(helpT: seq[array[0..3, string]], defVal: int,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "int", $defVal, parHelp ])

# int8
template argParse*(dst: int8, key: string, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting int8\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = int8(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: int8,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "int8", $defVal, parHelp ])

# int16
template argParse*(dst: int16, key: string, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting int16\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = int16(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: int16,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "int16", $defVal, parHelp ])

# int32
template argParse*(dst: int32, key: string, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting int32\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = int32(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: int32,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "int32", $defVal, parHelp ])

# int64
template argParse*(dst: int64, key: string, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting int64\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = tmp

template argHelp*(helpT: seq[array[0..3, string]], defVal: int64,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "int64", $defVal, parHelp ])

# uint
template argParse*(dst: uint, key: string, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting uint\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = uint(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: uint,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "uint", $defVal, parHelp ])

# uint8
template argParse*(dst: uint8, key: string, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting uint8\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = uint8(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: uint8,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "uint8", $defVal, parHelp ])

# uint16
template argParse*(dst: uint16, key: string, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting uint16\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = uint16(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: uint16,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "uint16", $defVal, parHelp ])

# uint32
template argParse*(dst: uint32, key: string, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting uint32\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = uint32(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: uint32,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "uint32", $defVal, parHelp ])

# uint64
template argParse*(dst: uint64, key: string, val: string, help: string) =
  var tmp: int
  if val == nil or parseInt(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting uint64\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = uint64(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: uint64,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "uint64", $defVal, parHelp ])

# float
template argParse*(dst: float, key: string, val: string, help: string) =
  if val == nil or parseFloat(strip(val), dst) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting float\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])

template argHelp*(helpT: seq[array[0..3, string]], defVal: float,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "float", $defVal, parHelp ])

# float32
template argParse*(dst: float32, key: string, val: string, help: string) =
  var tmp: float
  if val == nil or parseFloat(strip(val), tmp) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting float32\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])
  else: dst = float32(tmp)

template argHelp*(helpT: seq[array[0..3, string]], defVal: float32,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "float32", $defVal, parHelp ])

# float64
template argParse*(dst: float64, key: string, val: string, help: string) =
  if val == nil or parseFloat(strip(val), dst) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting float64\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])

template argHelp*(helpT: seq[array[0..3, string]], defVal: float64,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "float64", $defVal, parHelp ])
