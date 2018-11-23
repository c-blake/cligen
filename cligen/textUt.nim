from strutils import split, wordWrap, repeat
from terminal import terminalWidth

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
    var wrapped = wordWrap(row[last], maxLineWidth = wCol[last]).split("\n")
    result &= (if wrapped.len > 0: wrapped[0] else: "") & "\n"
    for j in 1 ..< len(wrapped):
      result &= repeat(" ", leader) & wrapped[j] & "\n"
    result &= rowSep

type C = int16      ##Type for edit cost values & totals
const Cmx = C.high
proc distDamerau*[T](A, B: openArray[T], maxDist=Cmx,
                     Cid=C(1), Csub=C(1), Cxpo=C(1), dI: var seq[C]): C =
  ## True Damerau(1964) distance with unrestricted transpositions.
  var n = A.len                         #ensure 2nd arg shorter (m < n)
  var m = B.len     #XXX Ukkonen/Berghel or even faster Myers/Hyyro?
  if abs(n - m) * int(Cid) >= int(maxDist):
    return maxDist
  let CsubA = min(C(2) * Cid, Csub)      #Can always do a sub w/del + ins
  template d(i, j: C): auto = dI[(C(m) + C(2))*(i) + (j)]
  template DA(i: C): auto = dI[(C(m) + C(2))*(C(n) + C(2)) + (i)]
  let BIG = C(n + m) * Cid
  dI.setLen((n + 2) * (m + 2) + 256)
  zeroMem(addr DA(0), 256 * sizeof(C))
  d(C(0), C(0)) = BIG
  for i in C(0) .. C(n):
    d(i+C(1), C(1)) = C(i) * Cid
    d(i+C(1), C(0)) = BIG
  for j in C(0) .. C(m):
    d(C(1), j+1) = C(j) * Cid
    d(C(0), j+1) = BIG
  for i in C(1) .. C(n):
    var DB = C(0)
    for j in C(1) .. C(m):
      let i1 = DA(C(B[j - 1]))
      let j1 = DB
      let cost = if A[i-1] == B[j-1]: C(0) else: C(1)
      if cost == 0:
        DB = j
      d(i+C(1), j+C(1)) = min(d(i1, j1) + (i-i1-C(1) + C(1) + j-j1-C(1)) * Cxpo,
                            min(d(i, j) + cost * CsubA,
                                min(d(i+1, j) + Cid,
                                    d(i  , j+1) + Cid)))
    DA(C(A[i-1])) = i
  return min(maxDist, d(C(n)+C(1), C(m)+C(1)))

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
