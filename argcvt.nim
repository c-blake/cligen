from parseutils import parseInt, parseFloat
from strutils   import `%`, join, split, wordWrap, repeat
from termwidth  import terminalWidth

proc keys*(parNm: string, shrt: string): string =
  result = if len(shrt) > 0: "--$1=, -$2=" % [ parNm, shrt ]
           else            : "--" & parNm & "="

template argRet*(code: int, msg: string) =
  ## argRet is a simple space-saving template to write msg and return a code.
  stderr.write(msg)                         # if code==0 send to stdout?
  return code

proc addPrefix*(prefix: string, multiline=""): string =
  result = ""
  for line in multiline.split("\n"):
    result &= prefix & line & "\n"

proc alignTable*(tab: seq[array[0..3, string]],
                 prefixLen=0, colGap=2, min4th=16): string =
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

## argParse and argHelp are a pair of related overloaded template helpers for
## each supported Nim type of optional parameter.  You may define new ones for
## your own custom types as needed wherever convenient in-scope of dispatch().
## argParse determines how string arguments are interpreted into native types
## while argHelp explains this interpretation to a command-line user.

## XXX add many more pairs for, e.g. all varieties of int, float.
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
  helpT.add([ keys, "toggle", $defVal, parHelp ]) # .join("\t") & "\n  "
  shortBool.add(sh)
  longBool.add(parNm)

# string
template argParse*(dst: string, key: string, val: string, help: string) =
  if val == nil:
    argRet(1, "Bad value nil for string param \"$1\"\n$2" % [ key, help ])
  dst = val

template argHelp*(helpT: seq[array[0..3, string]], defVal: string,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "string", "\"" & defVal & "\"", parHelp ])

# char
template argParse*(dst: char, key: string, val: string, help: string) =
  if val == nil or len(val) > 1:
    argRet(1, "Bad value nil/multi-char for char param \"$1\"\n$2" %
           [ key , help ])
  dst = val[0]

template argHelp*(helpT: seq[array[0..3, string]], defVal: char,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "char", $defVal, parHelp ])

# int
template argParse*(dst: int, key: string, val: string, help: string) =
  if val == nil or parseInt(strip(val), dst) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting int\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])

template argHelp*(helpT: seq[array[0..3, string]], defVal: int,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "int", $defVal, parHelp ])

# float
template argParse*(dst: float, key: string, val: string, help: string) =
  if val == nil or parseFloat(strip(val), dst) == 0:
    argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting float\n$3" %
           [ (if val == nil: "nil" else: val), key, help ])

template argHelp*(helpT: seq[array[0..3, string]], defVal: float,
                  parNm: string, sh: string, parHelp: string) =
  helpT.add([ keys(parNm, sh), "float", $defVal, parHelp ])
