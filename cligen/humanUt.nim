when (NimMajor,NimMinor,NimPatch) > (0,20,2):
  {.push warning[UnusedImport]: off.} # import-inside-include confuses used-system
import std/[strutils, parseutils]

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
  elif Bytes < m  *  K  : result = ff(Bytes/M, 2) & "M"
  elif Bytes < 99.5 * M : result = ff(Bytes/M, 2) & "M"
  elif Bytes < 100 * M  : result = "100M"
  elif Bytes < 995 * M  : result = ff(Bytes/M, 3) & "M"
  elif Bytes < m  *  M  : result = ff(Bytes/G, 2) & "G"
  elif Bytes < 99.5 * G : result = ff(Bytes/G, 2) & "G"
  elif Bytes < 100 * G  : result = "100G"
  elif Bytes < 995 * G  : result = ff(Bytes/G, 3) & "G"
  elif Bytes < m  *  G  : result = ff(Bytes/T, 2) & "T"
  elif Bytes < 99.5 * T : result = ff(Bytes/T, 2) & "T"
  elif Bytes < 100 * T  : result = "100T"
  else:                   result = ff(Bytes/T, 3) & "T"

when not (defined(cgCfgNone) and defined(cgNoColor)): # need BOTH to elide
 import std/tables

 when not declared(fromHex):
  proc fromHex[T: SomeInteger](s: string): T =
    let p = parseutils.parseHex(s, result)
    if p != s.len or p == 0:
      raise newException(ValueError, "invalid hex integer: " & s)

 let attrNames = {  #WTF: const compiles but then cannot look anything up
  "plain": "0", "bold":  "1", "faint":   "2", "italic": "3", "underline": "4",
  "blink": "5", "BLINK": "6", "inverse": "7", "struck": "9",
  "NONE":   "", "-bold":"22", "-faint": "22", "-italic":"23","-underline":"24",
  "-blink":"25","-BLINK":"25","-inverse":"27","-struck":"29",
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

 proc textAttrAliasClear*() = textAttrAliases.clear

 proc textAttrRegisterAliases*(colors: seq[string]) =
  for spec in colors:
    let cols = spec.split('=')
    if cols.len == 2:
      textAttrAlias(cols[0].strip, cols[1].strip)

 proc textAttrParse*(s: string): string =
  if s.len == 0: return
  var s = s
  while textAttrAliases.hasKey s:
    s = textAttrAliases[s]
  try: result = attrNames[s]
  except KeyError:
    if s.len >= 2:
      let prefix = if s[0] == 'b': "48;" else: "38;"
      if   s.len <= 3: result = prefix & "5;" & $(232 + parseInt(s[1..^1]))
      elif s.len == 4: # Above, xt256 grey scl, Below xt256 6*6*6 color cube
        let r = min(5, ord(s[1]) - ord('0'))
        let g = min(5, ord(s[2]) - ord('0'))
        let b = min(5, ord(s[3]) - ord('0'))
        result = prefix & "5;" & $(16 + 36*r + 6*g + b)
      elif s.len == 7: # True color
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

 const textAttrOff* = "\x1b[m"

 proc specifierHighlight*(fmt: string, pctTerm: set[char], plain=false, pct='%',
    openBkt="([{", closeBkt=")]}", keepPct=true, termInAttr=true): string =
  ## ".. %X(A1 A2)Ya .." -> ".. ON[A1 A2]%XYaOFF .."
  var term = pctTerm; term.incl pct     #Caller need not enter pct in pctTerm
  var other, attr, attrOn: string       #..Should maybe check xBkt^pctTerm=={}.
  var inPct = false
  var mchdBkt = false
  var bkt: char
  let attrOff = if plain: "" else: textAttrOff
  for c in fmt:
    if inPct:
      if bkt != '\0':
        if c == bkt:
          bkt = '\0'
          attrOn = textAttrOn(attr.split(), plain)
          attr.setLen(0)
          mchdBkt = true
        else: attr.add c
      else:
        if not mchdBkt and c in openBkt:
          bkt = closeBkt[openBkt.find(c)]
          attr.setLen(0)
        elif c in term or c == pct:
          if attrOn.len > 0: result.add attrOn
          result.add other
          if termInAttr and c != pct: result.add c
          if attrOn.len > 0: result.add attrOff
          attrOn.setLen(0)
          other.setLen(0)
          if not termInAttr and c != pct: result.add c
          mchdBkt = false
          inPct = c == pct
          if keepPct and c == pct: other.add c
        else: other.add c
    else:
      if c == pct:
        inPct = true
        if keepPct: other.add c
      else: result.add(c)
  if inPct and bkt == '\0':   # End of string is a simplified c in term branch
    if attrOn.len > 0: result.add attrOn
    result.add other
    if attrOn.len > 0: result.add attrOff

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

#NOTE: \-escape off only inside inline DB literals breaks any parser layering &
#I think blocks any 1-pass parse.  For now ``lit\eral`` -> <DB0>literal<DB1>.
#Also, the old parser/substitutor also failed in this same, way.
 iterator descape(s: string, escape='\\'): tuple[c: char; escaped: bool] =
  var escaping = false  # This just yields a char & bool escaped status
  for c in s:
    if escaping: escaping = false; yield (c, true)
    elif c == escape: escaping = true
    else: yield (c, false)

 type
  RstKind = enum rstNil, rstBeg,rstEnd, rstEsc, rstWhite,rstText, rstOpn,rstCls,
                 rstPunc, rstSS,rstDS,rstTS, rstSB,rstDB
  RstToken = tuple[kind: RstKind; text: string; ix: int]
 const rstMarks = { rstSS, rstDS, rstTS, rstSB, rstDB }
 const bktOpn = "([{<\"'"
 const bktCls = ")]}>\"'"
 const punc = { '-', ':', '/', '.', ',', ';', '!', '?' }

 let key2tok = { "singlestar": rstSS, "doublestar": rstDS, "triplestar": rstTS,
                 "singlebquo": rstSB, "doublebquo": rstDB }.toTable

 let rstMdSGRDefault* = { "singlestar": "italic      ; -italic"      ,
                          "doublestar": "bold        ; -bold"        ,
                          "triplestar": "bold italic ; -bold -italic",
                          "singlebquo": "underline   ; -underline"   ,
                          "doublebquo": "inverse     ; -inverse"     }.toTable
 type rstMdSGR* = object
   attr: Table[RstKind, tuple[on, off: string]]

 proc initRstMdSGR*(attrs=rstMdSGRDefault, plain=false): rstMdSGR =
  ## A hybrid restructuredText-Markdown-to-ANSI SGR/highlighter/renderer that
  ## does *only inline* font markup (single-|double-|triple-)``(*|`)`` since A) that
  ## is what is most useful displaying to a terminal and B) the whole idea of
  ## these markups is to be readable as-is.  Backslash escape & spacing work as
  ## usual to block adornment interpretation.  This proc inits ``rstMdSGR`` with
  ## a Table of {style: "open;close"} text adornments. ``plain==true`` will make
  ## the associated ``render`` proc merely remove all such adornments.
  result.attr = initTable[RstKind, tuple[on, off: string]]()
  for key, val in attrs:
    let c = val.split(';')
    if c.len != 2:
      stderr.write "[render] values must be ';'-separated on/off pairs\n"
    result.attr[key2tok[key]] =
      (textAttrOn(c[0].strip.split, plain), textAttrOn(c[1].strip.split, plain))

 iterator rstTokens(s: string): RstToken =
  var tok: RstToken = (rstBeg, "", -1)
  yield tok
  tok.kind = rstNil

  template doYield() =          # Maybe yield and if so reset token
    if tok.kind != rstNil:
      yield tok
      tok.text.setLen 0
      tok.kind = rstNil
      tok.ix = -1

  for c, escaped in s.descape:
    let op = bktOpn.find(c)     # -1 | index of open bracket
    let cl = bktCls.find(c)     # -1 | index of close bracket
    if escaped:
      doYield()
      tok.kind = rstEsc; tok.text.add c
    elif c in Whitespace:
      if tok.kind == rstWhite: tok.text.add c
      else: doYield(); tok.kind = rstWhite; tok.text.add c
    elif c == '*':
      if    tok.kind == rstSS: tok.kind = rstDS
      elif  tok.kind == rstDS: tok.kind = rstTS; doYield()
      else: doYield(); tok.kind = rstSS
    elif c == '`':
      if    tok.kind == rstSB: tok.kind = rstDB; doYield()
      else: doYield(); tok.kind = rstSB
    elif c in punc:
      if tok.kind == rstPunc: tok.text.add c
      else: doYield(); tok.kind = rstPunc; tok.text.add c
    elif op != -1:
      doYield()
      tok.kind = rstOpn; tok.text.add bktOpn[op]; tok.ix = op; doYield()
    elif cl != -1:
      doYield()
      tok.kind = rstCls; tok.text.add bktCls[cl]; tok.ix = cl; doYield()
    else:
      if tok.kind == rstText: tok.text.add c
      else: doYield(); tok.kind = rstText; tok.text.add c
  doYield()
  yield (rstEnd, "", -1)

# docutils.sourceforge.io/docs/ref/rst/restructuredtext.html: inline markup rec.
# Markup is done when the following patterns occur (where MARK = *|**|***|`|``,
# OPEN = [({<.. & CLOSE = ])}>..):
#   BegText|White|OPEN|BegPunc MARK nonWhite|[0]!=MchCLOSE          => Beg font
#   nonWhite                   MARK EndText|White|CLOSE|Esc|EndPunc => End font
 proc render*(r: rstMdSGR, rstOrMd: string): string =
  ## Translate restructuredText inline font markup (extended with triple star)
  ## to ANSI SGR/highlighted text via highlighting ``r``.
  var toks: seq[RstToken]       # Last 2 tokens + current decide what to do
  var mup = false               # Markup does not nest; mup==true => cannot Beg
  let none = ("", "")
  for tok in rstOrMd.rstTokens:
    if toks.len < 2:
      toks.add tok
      continue
    result.add toks[0].text
    if mup and toks[0].kind != rstWhite and toks[1].kind in rstMarks and
       tok.kind in {rstEnd, rstWhite, rstCls, rstEsc, rstPunc}:
      mup = false
      result.add r.attr.getOrDefault(toks[1].kind, none).off
    elif not mup and toks[0].kind in {rstBeg, rstWhite, rstOpn, rstPunc} and
         toks[1].kind in rstMarks and tok.kind != rstWhite:
      mup = true
      #XXX for rstOpn lexer tells us .ix; Should save & use above for rstCls
      result.add r.attr.getOrDefault(toks[1].kind, none).on
    toks[0] = toks[1]; toks[1] = tok    # shift
  for tok in toks:
    result.add tok.text
