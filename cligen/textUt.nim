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
                     Cid=1.C, Csub=1.C, Cxpo=1.C, dI: var seq[C]): C =
  ## True Damerau(1964) distance with unrestricted transpositions.
  var n = A.len                         #ensure 2nd arg shorter (m < n)
  var m = B.len     #XXX Ukkonen/Berghel or even faster Myers/Hyyro?
  if n < m:         #XXX Unlikely to matter for juat a few short strings.
    return distDamerau(B, A, maxDist, Cid, Csub, Cxpo, dI)
  if n - m >= int(maxDist) * int(Cid):
    return maxDist
  let CsubA = min(2.C * Cid, Csub)      #Can always do a sub w/del + ins
  template d(i, j: C): auto = dI[(m.C + 2.C)*(i) + (j)]
  template DA(i: C): auto = dI[(m.C + 2.C)*(n.C + 2.C) + (i)]
  let BIG = C(n + m) * Cid
  dI.setLen((n + 2) * (m + 2) + 256)
  zeroMem(addr DA(0), 256 * sizeof(C))
  d(0.C, 0.C) = BIG
  for i in 0.C .. n.C:
    d(i+1.C, 1.C) = C(i) * Cid
    d(i+1.C, 0.C) = BIG
  for j in 0.C .. m.C:
    d(1.C, j+1) = C(j) * Cid
    d(0.C, j+1) = BIG
  for i in 1.C .. n.C:
    var DB = 0.C
    for j in 1.C .. m.C:
      let i1 = DA(C(B[j - 1]))
      let j1 = DB
      let cost = if A[i-1] == B[j-1]: C(0) else: C(1)
      if cost == 0:
        DB = j
      d(i+1.C, j+1.C) = min(d(i1 , j1) + (i-i1-1.C + 1.C + j-j1-1.C) * Cxpo,
                            min(d(i,   j) + cost * CsubA,
                                min(d(i+1, j) + Cid,
                                    d(i  , j+1) + Cid)))
    DA(C(A[i-1])) = i
  return d(n.C+1.C, m.C+1.C)

proc suggestions*(wrong: string, rights: openArray[string], lim=3): seq[string]=
  let mxMx = 4.C                          #At least 1 more than d in dist[] <= d
  var buf: seq[C]
  var dist: seq[C]                        #Array parallel to `rights`
  for right in rights:                    #Distances can be slow; Do just once
    dist.add(distDamerau(right, wrong, maxDist=mxMx, dI=buf))
  for d in 1.C ..< mxMx:                  #Do not call if wrong == some right
    for i, right in rights:
      if right notin result and dist[i] <= d:
        result.add(right)
    if result.len >= lim:
      break
