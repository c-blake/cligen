from strutils import split, repeat, replace, count
from terminal import terminalWidth
import critbits
when NimVersion <= "0.19.8":
  import strutils
  proc wrapWords(x: string, maxLineWidth: int): string=wordWrap(x, maxLineWidth)
else:
  import std/wordwrap

proc wrap*(prefix: string, s: string): string =
  let w = terminalWidth() - 2*prefix.len
  if s.count("\n ") > 1:   #Leave alone if there is any indentation
    result = s
  else:
    result = wrapWords(s.replace("\n", " "), w)

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

proc alignTable*(tab: TextTab, prefixLen=0, colGap=2, minLast=16, rowSep="",
                 cols = @[0,1]): string =
  result = ""
  proc nCols(): int =
    result = 0
    for row in tab: result = max(result, row.len)
  var wCol = newSeq[int](nCols())
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
    var wrapped = if '\n' in row[last]: row[last].split("\n")
                  else: wrapWords(row[last],maxLineWidth=wCol[last]).split("\n")
    result &= (if wrapped.len > 0: wrapped[0] else: "") & "\n"
    for j in 1 ..< len(wrapped):
      result &= repeat(" ", leader) & wrapped[j] & "\n"
    result &= rowSep

type C = int16      ##Type for edit cost values & totals
const mxC = C.high
proc distDamerau*[T](a, b: openArray[T], maxDist=mxC,
                     idC=C(1), subC=C(1), xpoC=C(1), dI: var seq[C]): C =
  ## True Damerau(1964) distance with unrestricted transpositions.
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

from unicode import nil
proc printedLen*(a: string): int =
  ##Compute width when printed; Currently ignores "\e[..m" seqs&cnts utf8 runes.
  var inEscSeq = false
  var s = newStringOfCap(a.len)
  for c in a:
    if inEscSeq:
      if c == 'm': inEscSeq = false
    else:
      if c == '\e': inEscSeq = true
      else: s.add c
  result = unicode.runeLen s

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

proc toSetChar*(s: string): set[char] =
  ## Make & return character set built from a string.
  for c in s: result.incl c
