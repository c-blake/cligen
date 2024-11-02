from strutils import split, join, strip, repeat, replace, count, Whitespace,
                     startsWith, toUpper, toLowerAscii
from terminal import terminalWidth
import os, parseutils, critbits, math, ./mslice # math.^
when not declared(stderr): import std/syncio

type NoCSI_OSC* = object  ## Call-to-call state used by the noCSI_OSC iterator
  inCSI, inOSC, postEsc: bool

var nc0: NoCSI_OSC        ## A default `nc` which is all 0/false

iterator noCSI_OSC*(a: openArray[char], nc: var NoCSI_OSC = nc0): char =
  ## Iterate over chars in `a` skipping CSI/OSC term escape seqs (`"\e[..m"`,
  ## `"\e]..\e\\"`). See en.wikipedia.org/wiki/ANSI_escape_code "Fe Escape".
  ## To aid buffered use, if provided, `nc` can propagate parser state.
  var i = 0
  while i < a.len:
    let c = a[i]
    if nc.inCSI:
      if ord(c) in 0x40..0x7E: nc.inCSI = false
    elif nc.inOSC:
      if c == '\e':
        if (i + 1) < a.len and a[i + 1] == '\\':
          nc.inOSC = false
          inc i
      elif c == '\a':
        nc.inOSC = false
    elif nc.postEsc:
      if   c == '[': nc.inCSI = true
      elif c == ']': nc.inOSC = true
      else:
        yield '\e'
        yield c
      nc.postEsc = (c == '\e')
    elif c == '\e':
      nc.postEsc = true
    else: yield c
    inc i

proc stripEsc*(a: openArray[char]): string =
  ## Use `noCSI_OSC` to give `a` without non-rendering terminal escape seqs.
  result = newStringOfCap(a.len)
  for c in a.noCSI_OSC: result.add c

proc stripSGR*(a: openArray[char]): string = a.stripEsc ## Alias for `stripEsc`.

const runeBytes: array[256, int8] = [ # adix/sequint could do in 96B, not 256B
   0i8,0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,  # 0x00
   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,  # 0x10
   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,  # 0x20
   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,  # 0x30
   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,  # 0x40
   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,  # 0x50
   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,  # 0x60
   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,  # 0x70
  -1, -1, -1, -1,  -1, -1, -1, -1,  -1, -1, -1, -1,  -1, -1, -1, -1,  # 0x80
  -1, -1, -1, -1,  -1, -1, -1, -1,  -1, -1, -1, -1,  -1, -1, -1, -1,  # 0x90
  -1, -1, -1, -1,  -1, -1, -1, -1,  -1, -1, -1, -1,  -1, -1, -1, -1,  # 0xa0
  -1, -1, -1, -1,  -1, -1, -1, -1,  -1, -1, -1, -1,  -1, -1, -1, -1,  # 0xb0
   1,  1,  1,  1,   1,  1,  1,  1,   1,  1,  1,  1,   1,  1,  1,  1,  # 0xc0
   1,  1,  1,  1,   1,  1,  1,  1,   1,  1,  1,  1,   1,  1,  1,  1,  # 0xd0
   2,  2,  2,  2,   2,  2,  2,  2,   2,  2,  2,  2,   2,  2,  2,  2,  # 0xe0
   3,  3,  3,  3,   3,  3,  3,  3,   4,  4,  4,  4,   5,  5, -1, -1]  # 0xf0

proc printedLen*(a: openArray[char]): int =
  ## Rendered width in terminal cells, accounting for ANSI SGR colors &| utf8.
  ## This counts invalid start-bytes as 1 cell.
  var skip = 0
  for c in a.noCSI_OSC:
    if skip > 0: dec skip
    else:
      inc result
      when defined(branchyRuneLen):
        skip = if   c.uint <= 127: 0
               elif c.uint shr 5 == 0b110:     1
               elif c.uint shr 4 == 0b1110:    2
               elif c.uint shr 3 == 0b11110:   3
               elif c.uint shr 2 == 0b111110:  4
               elif c.uint shr 1 == 0b1111110: 5
               else: 0
      else:
        skip = runeBytes[c.int]

iterator paragraphs*(s: string, indent = {' ', '\t'}):
    tuple[pre: bool, para: string] =
  ## This iterator frames paragraphs in `s` delimited either by double-newline
  ## or by changes in indent status.  Any indented line is considered a whole,
  ## pre-formatted paragraph.  This indent rule allows easy author control over
  ## what text is eligible for word-wrapping.
  var para = ""
  for ln in mSlices(s.toMSlice, '\n'):  # stdlib split iterator yields a final
    let line = $ln                      #..empty line; `mSlices` does not
    if line.len == 0:           # Blank line => end of para; yield accumulated
      if para.len > 0:
        yield (false, move para)
        para.setLen 0
      yield (true, "")          # Blanks in input => blanks in output
    elif line[0] in indent:     # Any kind of indent => pre-formatted para
      if para.len > 0:
        yield (false, move para)
        para.setLen 0
      yield (true, line)
    else:                       # Non-indented, non-empty line: accumulate
      para.add '\n'; para.add line
  if para.len > 0:
    yield (false, para)

iterator boundWrap(w: openArray[int], m=80): Slice[int] =
  ## Yield slices of ``w`` corresponding to blocks of all ``< m - 1`` or else a
  ## singleton slice ``j..j`` of just an overflowing word for those.
  var i, j: int
  while i < w.len:
    while j < w.len and w[j] < m - 1:
      j.inc
    if j < w.len:
      j.inc
    yield i ..< j
    i = j

iterator optimalWrap(w: openArray[int], words: openArray[string], m=80,
                     p=3): Slice[int] =
  ## Yield slices of word widths `w` corresponding to each line for a wrap that
  ## minimizes badness of Lp norm(excess space).  Run-time is O(w.len^2).  If a
  ## `w[j] > m` then that word is simply put on a line by itself that overflows.
  # Solve by a dynamic programming solution to the recursion (PRINT-NEATLY):
  #   c[j] = if j==0: 0 else:  min (c[i]+C[i,j])
  #                          i=0..<j     |-cost to put words from i..<j in line
  # Handle double space after [?.] by adding a space post-splitr, not counting
  # it right at line-overflow time, and stripping stray space post-join.
  let n = w.len
  var c = newSeq[int](n)    # c[i]=min cost of line in which arr[i] is 1st word
  var r = newSeq[int](n)    # r[i]=ix[last word in ln where word arr[i] is 1st]
  r[n - 1] = n - 1
  for i in countdown(n - 2, 0):
    var curr = -1           # Cancel very first +1
    c[i] = int.high
    for j in i ..< n:       # upper triangle
      curr += w[j] + 1
      if curr > m:          # overflowed `m`
        if curr == m + 1 and words[j][^1] == ' ':
          curr -= 1
        else:
          break
      let cost = if j == n - 1: 0 else: c[j + 1] + ((m - curr)^p)
      if cost < c[i]:       # track min & location
        c[i] = cost
        r[i] = j
  var i = 0                 # yield slices defining each line
  while i < w.len:
#   if r[i]<i: echo "ERROR" # gc:orc,arc,boehm,regions ok; default,markSweep bad
    yield i..r[i]
    i = r[i] + 1

let ttyWidth* = terminalWidth()
var errno {.importc, header: "<errno.h>".}: cint
errno = 0 #XXX stdlib.terminal should probably clear errno for all client code

proc wrapWidth*(envVar: string, defaultWidth=ttyWidth): int =
  result = defaultWidth
  if existsEnv(envVar):
    let ev = getEnv(envVar)
    if ev != "AUTO" and parseInt(ev, result) != ev.len:
      raise newException(ValueError, envVar & " must be an integer")

proc extraSpace(w0, sep, w1: string): bool {.inline.} =
  # True if a non-final token ending in '.' should get extra space.  This always
  # returns true if there is >1 space in ``sep``.  At the end of a line when the
  # next line starts with a valid sentence opener there is still an ambiguity.
  # So, authors can add an extra space to disambiguate but EOL whitespace can be
  # unpopular (as can double space sentence separation, but I find it nice in
  # monospace fonts).  So, additionally we use a heuristic to suppress the space
  # if the line ends with "[A-Z].*[a-z]\." like "Dr." which often expects the
  # next word capitalized but not end-of-sentence.  This heuristic fails if it
  # really is EOSentence at EOL like "Yes." or "See the Dr.".  These failures
  # are hopefully rare enough that space at the EOL is not onerous or else the
  # author wanted to single-space all their sentences anyway which always works.
  const sentStart = { 'A'..'Z', '\'', '"', '`', '(', '[', '{', '0'..'9' }
  (sep.len > 1) or ('\n' in sep and w1[0] in sentStart and
    not (w0.len > 2 and w0[0] in {'A'..'Z'} and w0[^2] in {'a'..'z'}))

proc wrap*(s: string; maxWidth=ttyWidth, power=3, prefixLen=0): string =
  ## Multi-paragraph with indent==>pre-formatted optimal line wrapping using
  ## the badness metric *sum excessSpace^power*.
  if maxWidth == -1: return s           # -1 => wrap disabled
  let maxW = if maxWidth == 0: ttyWidth else: maxWidth
  let maxWidth = maxW  -  2 * prefixLen
  for tup in s.paragraphs:
    let (pre, para) = tup
    if pre:
      result.add para; result.add '\n'
    else:
      var words, sep: seq[string]
      discard para.strip.splitr(words, wspace, sp=sep.addr)
      for i in 0 ..< words.len:
        if words[i][^1] in {'?','!'} or (words[i][^1]=='.' and i+1<words.len and
              extraSpace(words[i], sep[i], words[i+1])):
          words[i].add ' '
      var w = newSeq[int](words.len)
      for i, word in words:
        w[i] = word.printedLen
      for slice in boundWrap(w, maxWidth):
        if slice.len == 0: discard
        elif slice.len == 1:
          result.add words[slice][0]; result.add '\n'
        else:
          for line in optimalWrap(w[slice], words[slice], maxWidth, power):
            let adjSlice = Slice[int](a: slice.a + line.a, b: slice.a + line.b)
            result.add join(words[adjSlice], " ").strip(false); result.add '\n'
  if result.len > 0 and result[^1] == '\n':
    result.setLen result.len - 1        # make more like `strutils.wrapWords`

proc addPrefix*(prefix: string, multiline=""): string =
  result = ""
  var lines = multiline.split("\n")
  if len(lines) > 1:
    for line in lines[0 .. ^2]:
      result &= prefix & line & "\n"
  if len(lines) > 0:
    if len(lines[^1]) > 0:
      result &= prefix & lines[^1] & "\n"

type TextTab* = seq[seq[string]]

proc mx[T](x: openArray[T]): T =
  result = T.low
  for e in x: result = max(result, e)

proc alignTable*(tab: TextTab, prefixLen=0, colGap=2, minLast=16, rowSep="",
    cols = @[0,1], attrOn = @["",""], attrOff = @["",""], aligns = "",
    width=ttyWidth, measure=printedLen): string =
  let colsMx = cols.mx + 1
  let aligns = if aligns.len >= colsMx: aligns else: repeat("L", colsMx)
  result = ""
  if tab.len == 0: return
  proc nCols(): int =
    result = 0
    for row in tab: result = max(result, row.len)
  var wCol = newSeq[int](nCols())
  let last = cols[^1]
  for row in tab:
    for c in cols: wCol[c] = max(wCol[c], row[c].measure)
  let wTerm = (if width==0:ttyWidth elif width == -1:1000 else:width)-prefixLen
  var leader = (cols.len - 1) * colGap
  for c in cols[0 .. ^2]: leader += wCol[c]
  template doCol(c: int): untyped =
    let aln  = if aligns[c] == 'l': 'L' else: aligns[c]
    let inr  = attrOn[c] & row[c] & attrOff[c]
    let extr = wCol[c] - row[c].measure
    if   aln == 'L': result &= inr & repeat(" ", extr + colGap)
    elif aln == 'R': result &= repeat(" ", extr) & inr & repeat(" ", colGap)
    elif aln == 'C':
      let nL = extr div 2
      result &= repeat(" ", nL) & inr & repeat(" ", extr - nL + colGap)
  for row in tab:
    for c in cols[0 .. ^2]: doCol c
    if aligns[^1] != 'L': # Only default Cap L eligible for word-wrap
      doCol cols.len - 1
      result &= '\n'
      continue
    let wLast = max(minLast, wTerm - leader)
    var wrapped = if width == -1 or '\n' in row[last]: row[last].split("\n")
                  else: wrap(row[last], wLast).split("\n")
    result &= attrOn[last] & (if wrapped.len>0: wrapped[0] else: "")
    if wrapped.len == 1:
      result &= attrOff[last] & "\n" & rowSep
    else:
      result &= '\n'
      for j in 1 ..< wrapped.len - 1:
        result &= repeat(" ", leader) & wrapped[j] & "\n"
      result &= repeat(" ",leader) & wrapped[^1] & attrOff[last] & "\n" & rowSep

type C = int16      ##Type for edit cost values & totals
const mxC = C.high
proc distDamerau*[T](a, b: openArray[T], maxDist=mxC,
                     idC=C(1), subC=C(1), xpoC=C(1), dI: var seq[C]): C =
  ## True Damerau (1964) distance with unrestricted transpositions (not OSA) and
  ## user cost scales for ins-del, substitute, transposition.  For details see:
  ## https://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance
  var n = a.len                         #ensure 2nd arg shorter (m < n)
  var m = b.len     #XXX Ukkonen/Berghel or even faster Myers/Hyyro?
  if abs(n - m) * int(idC) >= int(maxDist):
    return maxDist
  let subCeff = min(C(2) * idC, subC)   #effective cost; Can sub w/del+ins
  template d(i, j: C): auto = dI[(C(m) + C(2))*(i) + (j)]
  template dA(i: C): auto = dI[(C(m) + C(2))*(C(n) + C(2)) + (i)]
  let big = C(n + m) * idC
  dI.setLen((n + 2) * (m + 2) + 256)
  zeroMem(addr dA(0), 256 * sizeof(C))
  d(C(0), C(0)) = big
  for i in C(0) .. C(n):
    d(i+C(1), C(1)) = C(i) * idC
    d(i+C(1), C(0)) = big
  for j in C(0) .. C(m):
    d(C(1), j+1) = C(j) * idC
    d(C(0), j+1) = big
  for i in C(1) .. C(n):
    var dB = C(0)
    for j in C(1) .. C(m):
      let i1 = dA(C(b[j - 1]))
      let j1 = dB
      let cost = if a[i-1] == b[j-1]: C(0) else: C(1)
      if cost == 0:
        dB = j
      d(i+C(1), j+C(1)) = min(d(i1, j1) + (i-i1-C(1) + C(1) + j-j1-C(1)) * xpoC,
                            min(d(i, j) + cost * subCeff,
                                min(d(i+1, j) + idC,
                                    d(i  , j+1) + idC)))
    dA(C(a[i-1])) = i
  return min(maxDist, d(C(n)+C(1), C(m)+C(1)))

proc initCritBitTree*[T](): CritBitTree[T] =
  ##A constructor sometimes helpful when replacing ``Table[string,T]`` with
  ##``CritBitTree[T]``.
  discard

when not declared(toCritBitTree):
  proc toCritBitTree*[T](pairs: openArray[(string, T)]): CritBitTree[T] =
    ##Like ``toTable`` but for ``CritBitTree[T]`` which requires string keys.
    for key, val in items(pairs):
      result[key] = val

proc keys*[T](cb: CritBitTree[T]): seq[string] =
  for k in cb.keys: result.add k

proc getAll*[T](cb: CritBitTree[T], key:string): seq[tuple[key:string, val: T]]=
  ##A query function sometimes helpful in making ``CritBitTree[T]`` code more
  ##like ``Table[string,T]`` code. ``result.len > 1`` only on ambiguous matches.
  if key in cb:                 #exact match
    result.add( (key, cb[key]) )
    return
  for k, v in cb.pairsWithPrefix(key):
    result.add( (k, v) )

proc keys*[T](x: seq[tuple[key: string, val: T]]): seq[string] =
  ##An extractor of just the ``key`` part of a ``seq[(key,val)]``.
  {.push hint[XDeclaredButNotUsed]: off.}
  for tup in x:
    let (k, v) = tup; result.add(k)
  {.pop.}

proc suggestions*[T](wrong: string; match, right: openArray[T],
                     enoughResults=3, unrelatedDistance=C(4)): seq[string] =
  ## Return entries from `right` if the parallel entry in `match` is "close"
  ## to `wrong` in order of (in Damerau distance units).  Considering further
  ## distances is halted once result has `enoughResults` (but all suggestions
  ## for a given distance are included).  Matches >= `unrelatedDistance` are
  ## not considered.
  var dI, dist: seq[C]        #dI for Damerau & seq parallel to `match`,`right`
  if match.len != right.len:
    raise newException(ValueError, "match.len must equal right.len")
  for m in match:                         #Distance calc slow => save answers
    dist.add(distDamerau(wrong, m, maxDist=C(unrelatedDistance), dI=dI))
  for d in C(0) ..< C(unrelatedDistance):  #Expanding distances from zero
    for i in 0 ..< match.len:
      if right[i] notin result and dist[i] <= d:
        result.add(right[i])
    if result.len >= enoughResults:
      break

proc match*[T](cb: CritBitTree[T]; key, tag: string; msg: var string,
               suppress=false): tuple[key: string, val: T] =
  ## One stop lookup of a key in `cb` giving either the (key, value) matched or
  ## an ambiguous|unknown error message with possible suggestions if non-empty,
  ## unless ``suppress`` is true in which case msg is simply non-empty. ``tag``
  ## is a category for the message, like 'color' or such.
  var ks: seq[string]
  for k in cb.keysWithPrefix(key):
    if k == key:
      return (k, cb[k])                     #Exact match
    ks.add k
  if ks.len == 1:                           #Unique prefix match
    return (ks[0], cb[ks[0]])
  if ks.len > 1:                            #Ambiguous prefix match
    msg = "Ambiguous "
    if not suppress:                        #Skip string build if will not use
      msg = (msg & tag & " prefix \"" & key & "\" matches:\n  " &
             ks.join("\n  ") & "\n")
  else:                                     #No match
    msg = "Unknown "
    if not suppress:                        #Skip calc if will not use
      var allKeys: seq[string]
      for k in cb.keys: allKeys.add k
      let sugg = suggestions(key, allKeys, allKeys)
      msg = msg & tag & " \"" & key & "\"." & (if sugg.len == 0: "" else:
            "  Maybe you meant one of:\n  " & sugg.join(" ")) & "\n"

proc match*[T](cb: CritBitTree[T]; key, tag: string; err=stderr):
              tuple[key: string, val: T] =
  ##Wrapper around above ``match`` that on failure writes user-friendly messages
  ##to ``err`` (``nil`` suppresses this) and raises ``KeyError`` with a message
  ##that starts with "Ambiguous" or "Unknown".
  var msg: string
  result = cb.match(key, tag, msg, err == stdin)
  if msg.len == 0: return                   #exact/unique found; done
  if err != nil: err.write msg
  if msg.startsWith("Ambiguous"):
    raise newException(KeyError, "Ambiguous " & tag & " " & key)
  raise newException(KeyError, "Unknown " & tag & " " & key)

proc termAlign*(s: string, count: Natural, padding = ' '): string =
  ## Just like ``strutils.align`` but assess width via ``printedLen``.
  let pads = count - s.printedLen
  if pads > 0:
    result = newString(s.len + pads)
    for i in 0 .. pads-1: result[i] = padding
    for i in pads .. s.len+pads-1: result[i] = s[i - pads]
  else:
    result = s

proc termAlignLeft*(s: string, count: Natural, padding = ' '): string =
  ## Just like ``strutils.alignLeft`` but assess width via ``printedLen``.
  let pads = count - s.printedLen
  if pads > 0:
    result = newString(s.len + pads)
    if s.len > 0:
      result[0 .. s.len-1] = s
    for i in s.len ..< s.len + pads:
      result[i] = padding
  else:
    result = s

iterator unescaped*(s: string): char =
  ## Handles 1-byte octal, \[abtnvfre], and \xDD hex escapes
  let hexdigits = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
                    'a', 'b', 'c', 'd', 'e', 'f'}
  proc toHexDig(c: char): int =
    if c <= '9': ord(c) - ord('0') else: 10 + ord(c) - ord('a')
  var i = 0
  while i < s.len:
    case s[i]
    of '\\':
      if i+1 >= s.len: raise newException(ValueError, "incomplete escaped char")
      case s[i+1]
      of '0' .. '7': yield chr(ord(s[i+1]) - ord('0')); inc i, 2
      of 'a': yield chr(0x07); inc i, 2 # bell
      of 'b': yield chr(0x08); inc i, 2 # backspace
      of 't': yield chr(0x09); inc i, 2 # horizontal tab
      of 'n': yield chr(0x0A); inc i, 2 # new line
      of 'v': yield chr(0x0B); inc i, 2 # vertical tab
      of 'f': yield chr(0x0C); inc i, 2 # form feed
      of 'r': yield chr(0x0D); inc i, 2 # carriage ret
      of '\\':yield chr(0x5C); inc i, 2 # backslash
      of 'e': yield chr(0x1B); inc i, 2 # escape
      else:
        if i + 3 >= s.len:
          raise newException(ValueError, "incomplete 2-nibble hex escape")
        if s[i+1].toLowerAscii != 'x':
          raise newException(ValueError, "hex escape not of form \\xHH")
        let dhi = toLowerAscii(s[i+2])
        let dlo = toLowerAscii(s[i+3])
        if dhi notin hexdigits or dlo notin hexdigits:
          raise newException(ValueError, "non-hex escape: " & s[i..i+3])
        yield char(toHexDig(dhi)*16 + toHexDig(dlo))
        inc i, 4
    else:
      yield s[i]; inc i

proc toSetChar*(s: string, unescape=false): set[char] =
  ## Make & return character set built from a string, maybe un-escaping.
  if unescape: (for c in s.unescaped: result.incl c)
  else: (for c in s: result.incl c)
