import math, strutils, algorithm, sets, tables, parseutils, posix, textUt
when not declared(initHashSet):
  proc initHashSet*[T](): HashSet[T] = initSet[T]()
  proc toHashSet*[T](keys: openArray[T]): HashSet[T] = toSet[T](keys)

proc parseInt*(s: string, valIfNAN: int): int =
  ##A helper function to parse ``s`` into an integer, but default to some value
  ##when ``s`` is not an number at all.
  if parseutils.parseInt(s, result) == 0: result = valIfNAN

proc cmpN*(a, b: string): int =
  ##Cmp strs w/"to end of string" numeric substrs as nums.  Eg., "x.20" >"x.1".
  var i: int                              #Need to scan to first differing byte
  let n = min(a.len, b.len)               #..& then if num parse & cmp as such.
  while i < n:                            #May have >0 eql num substr pre-diff
    while i < n and a[i] == b[i]: i.inc   #Scan for diff byte
    if i == n: return cmp(a.len, b.len)   #Shorter strings are <
    if not (a[i].isDigit and b[i].isDigit):
      return cmp(a[i], b[i])
    while i > 0 and a[i-1].isDigit:       #Scan bk to num start; b=a up to here
      i.dec                               #i<-beg of common numeric pfx, if any.
    var x, y: BiggestInt
    try:
      discard parseBiggestInt(a, x, i)
      discard parseBiggestInt(b, y, i)
    except ValueError:                    #out of bounds
      return cmp(a, b)
    return cmp(x, y)

proc humanReadable4*(bytes: uint, binary=false): string =
  ## A low-precision always <= 4 text columns human readable size formatter.
  ## If binary is true use power of 2 units instead of SI/decimal units.
  let K = if binary: float(1.uint shl 10) else: 1e3
  let M = if binary: float(1.uint shl 20) else: 1e6
  let G = if binary: float(1.uint shl 30) else: 1e9
  let T = if binary: float(1.uint shl 40) else: 1e12
  let m = if binary: 1024.0               else: 1000.0
  var Bytes = bytes.float64
  proc ff(f: float64, p: range[-1..32]=2): string {.inline.} =
    let s = formatBiggestFloat(f, precision=p)
    if s[^1] == '.': s[0..^2] else: s
  if   Bytes <= 9999    : result = $bytes
  elif Bytes < 99.5 * K : result = ff(Bytes/K, 2) & "K"
  elif Bytes < 100 * K  : result = "100K"
  elif Bytes < 995 * K  : result = ff(Bytes/K, 3) & "K"
  elif Bytes <  m  * K  : result = ff(Bytes/M, 2) & "M"
  elif Bytes < 99.5 * M : result = ff(Bytes/M, 2) & "M"
  elif Bytes < 100 * M  : result = "100M"
  elif Bytes < 995 * M  : result = ff(Bytes/M, 3) & "M"
  elif Bytes <  m  * M  : result = ff(Bytes/G, 2) & "G"
  elif Bytes < 99.5 * G : result = ff(Bytes/G, 2) & "G"
  elif Bytes < 100 * G  : result = "100G"
  elif Bytes < 995 * G  : result = ff(Bytes/G, 3) & "G"
  elif Bytes <  m  * G  : result = ff(Bytes/T, 2) & "T"
  elif Bytes < 99.5 * T : result = ff(Bytes/T, 2) & "T"
  elif Bytes < 100 * T  : result = "100T"
  else:                   result = ff(Bytes/T, 3) & "T"

when not declared(fromHex):
  proc fromHex[T: SomeInteger](s: string): T =
    let p = parseutils.parseHex(s, result)
    if p != s.len or p == 0:
      raise newException(ValueError, "invalid hex integer: " & s)

let attrNames = {  #WTF: const compiles but then cannot look anything up
  "plain": "0", "bold":  "1", "faint":   "2", "italic": "3", "underline": "4",
  "blink": "5", "BLINK": "6", "inverse": "7", "struck": "9", "NONE":      "",
  "black"   : "30", "red"      : "31", "green"    : "32", "yellow"   : "33",#DkF
  "blue"    : "34", "purple"   : "35", "cyan"     : "36", "white"    : "37",
  "BLACK"   : "90", "RED"      : "91", "GREEN"    : "92", "YELLOW"   : "93",#LiF
  "BLUE"    : "94", "PURPLE"   : "95", "CYAN"     : "96", "WHITE"    : "97",
  "on_black": "40", "on_red"   : "41", "on_green" : "42", "on_yellow": "43",#DkB
  "on_blue" : "44", "on_purple": "45", "on_cyan"  : "46", "on_white" : "47",
  "on_BLACK":"100", "on_RED"   :"101", "on_GREEN" :"102", "on_YELLOW":"103",#LiB
  "on_BLUE" :"104", "on_PURPLE":"105", "on_CYAN"  :"106", "on_WHITE" :"107"
}.toTable

var textAttrAliases = initTable[string, string]()

proc textAttrAlias*(name, value: string) =
  textAttrAliases[name] = value

proc textAttrParse*(s: string): string =
  if s.len == 0: return
  var s = s
  while textAttrAliases.hasKey s:
    s = textAttrAliases[s]
  try: result = attrNames[s]
  except KeyError:
    if s.len >= 2:
      let prefix = if s[0] == 'b': "48;" else: "38;"
      if   s.len <= 3: result = $(232 + parseInt(s[1..^1])) #xt256 grey scl
      elif s.len == 4:
        let r = max(5, ord(s[1]) - ord('0'))
        let g = max(5, ord(s[2]) - ord('0'))
        let b = max(5, ord(s[3]) - ord('0'))
        result = prefix & "5;" & $(16 + 36*r + 6*g + b)
      elif s.len == 7:
        let r = fromHex[int](s[1..2])
        let g = fromHex[int](s[3..4])
        let b = fromHex[int](s[5..6])
        result = prefix & "2;" & $r & ";" & $g & ";" & $b
    if result.len == 0:
      raise newException(ValueError, "bad text attr spec \"" & s & "\"")

proc textAttrOn*(spec: seq[string], plain=false): string =
  if plain: return
  var components: seq[string]          #Build \e[$A;3$F;4$Bm for attr A,colr F,B
  for word in spec: components.add(textAttrParse(word))
  if components.len>0 and "" notin components: "\x1b["&components.join(";")&"m"
  else: ""

const textAttrOff* = "\x1b[0m"

proc specifierHighlight*(fmt: string, pctTerm: set[char], plain=false, pct='%',
                         openBkt = { '{','[' }, closeBkt = { '}',']' }): string=
  ## ".. %X[{A1 A2}]Ya .." -> ".. AttrOn[A1 A2]%XYaAttrOff .."
  var term = pctTerm; term.incl pct     #Caller need not enter pct in pctTerm
  var other, attr, attrOn: string       #..Should maybe check xBkt^pctTerm=={}.
  var inPct, inBkt: bool
  let attrOff = if plain: "" else: textAttrOff
  for c in fmt:
    if inPct:
      if inBkt:
        if c in closeBkt:
          inBkt = false
          attrOn = textAttrOn(attr.split(), plain)
          attr.setLen(0)
        else:
          attr.add c
      else:
        if c in openBkt:
          inBkt = true
          attr.setLen(0)
        elif c in term:
          inPct = false
          if attrOn.len > 0: result.add attrOn
          result.add other; result.add c
          if attrOn.len > 0: result.add attrOff
          attrOn.setLen(0)
          other.setLen(0)
        else: other.add c
    else:
      if c == '%': inPct = true; other.add c
      else: result.add(c)

proc humanDuration*(dt: int, fmt: string, plain=false): string =
  ## fmt is divisor-aka-numerical-unit-in-seconds unit-text [attrs]
  let cols = fmt.splitWhitespace
  let attrOff = if plain: "" else: textAttrOff
  try:
    if cols.len < 2: raise newException(ValueError, "")
    var dts: string
    if '/' in cols[0]:
      let div_dec = cols[0].split('/')
      let dec = parseInt(div_dec[1])
      dts = formatFloat(dt.float / parseInt(div_dec[0]).float, ffDecimal, dec)
    else:
      dts = $int(dt.float / parseInt(cols[0]).float)
    if cols.len > 2: result.add textAttrOn(cols[2..^1], plain)
    result.add dts
    if cols[1].startsWith('<'):
      result.add cols[1][1..^1]
    else:
      result.add " "
      result.add cols[1]
    if cols.len > 2: result.add attrOff
  except:
    raise newException(ValueError, "bad humanDuration format \"" & fmt & "\"")
