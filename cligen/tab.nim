import std/[math, strutils, algorithm, tables, parseutils, posix]
from std/unicode import nil

proc colPad*(cw: var seq[int]; fw=80, pm=999, m=1, j = -1) =
  ##Pad layout of column widths ``cw`` with up to ``pm`` spaces per major col,
  ##not overflowing the full width ``fw``.  ``m`` is the stride over columns,
  ##and ``j`` is the end relative offset of the minor column receiving padding.
  let nc = cw.len
  if nc mod m != 0: raise newException(ValueError, "cw.len mod m != 0")
  if -j > m: raise newException(ValueError, "-j > m")
  let ncMaj = nc div m
  var excess = fw - sum(cw)               #Distribute excess space -> gaps
  var added = 0
  var c = m + j
  while excess > 0 and added < ncMaj * pm: #Add at most pm spc per majcol total
    cw[c].inc
    added.inc
    excess.dec
    if nc > m:
      c = (c + m) mod (nc - m)            #cycle index c over columns by step m

proc rowcol(r,c: var int; n,nc: int) =
  let d = n div nc  #do r=ceil(n/nc), c=nc sets
  let m = n mod nc
  r = d + (if m != 0: 1 else: 0)
  c = nc

proc colOptimize*(lens: seq[int]; W=80, gap=1, mx=999, m=1; nr: var int): int =
  ##Return number of columns to minimize the number of rows. ``lens`` should be
  ##rendered terminal widths, not string lengths & entries can be <0 (abs used).
  ##``m`` is the column stride.  The units of ``mx`` are also minor columns.
  proc most(lens: seq[int]; a, b, m: int): int =
    for j in 0 ..< m:
      var subMx = 0
      for i in countup(a, b-1, m):
        subMx = max(subMx, abs(lens[i + j]))
      result += subMx
  proc totalWidth(lens: seq[int]; gap, n, m, nr, nc: int): int =
    let ncMaj = nc div m
    for c in 0 ..< ncMaj:
      let a = nr * m * c
      let b = min(n, nr * m * (c + 1))
      result += lens.most(a, b, m) + gap
    result -= gap                       #Last col needs no inter-col gap
  let n = lens.len
  if n mod m != 0: raise newException(ValueError, "lens.len mod m != 0")
  var nrTry, nc, ncTry: int
  nc = m
  rowcol(nr, result, n, nc)             #Start with m minor columns
  while nr > 1:                         #Stop when everything fits in 1 row
    nrTry = nr; ncTry = nc
    while nrTry >= nr:                  #ncTry += m, with nrTry carry along and
      rowcol(nrTry, ncTry, n, ncTry+m)  #ensuring more columns reduces nrTry.
    if ncTry > mx or totalWidth(lens, gap, n, m, nrTry, ncTry) > W:
      break                             #Exceeded usr-spec col or width limits
    nr = nrTry; nc = ncTry              #Fit!  Update accepted vars & try more
  rowcol(nr, result, n, nc)

proc layout*(lens: seq[int]; W,gap,mx,m: int; nr,nc: var int): seq[int] =
  let n = lens.len
  nc = colOptimize(lens, W, gap, mx, m, nr)
  let ncMaj = nc div m
  for c in 0 ..< ncMaj:
    let a = nr * m * c
    let b = min(nr * m * (c + 1), n)    #1 column ahead, but final can be short
    for j in 0 ..< m:
      var subMx = 0
      for i in countup(a, b-1, m):
        subMx = max(subMx, abs(lens[i + j]))
      result.add subMx                  #Could make this explicit rather than
    result[^1] += gap                   #..the slower add/^1 indexing easily.
  result[^1] -= gap                     #Very last col needs no inter-col gap

proc sortByWidth*(lens: seq[int]; m, nr, nc: int): seq[int] =
  result.setLen lens.len div m
  var x = newSeq[tuple[mlen: int, ix: int]](nr)
  let ncMaj = nc div m
  let n = lens.len
  for c in 0 ..< ncMaj:
    let a = nr * m * c
    let b = min(nr * m * (c + 1), n)    #1 column ahead, but final can be short
    var r = 0
    for i in countup(a, b-1, m):
      var tot = 0
      for j in 0 ..< m: tot += abs(lens[i + j])
      x[r].mlen = -tot
      x[r].ix   = i
      r.inc
    x.setLen(r)                         #This only ever shortens FINAL column
    x.sort(system.cmp)                  #sort by descending len (printedLen)
    while r > 0:                        #write sorted back to arrays
      r.dec
      result[nr * c + r] = x[r].ix

proc sortByWidth*(strs: var seq[string]; lens: var seq[int]; m, nr, nc: int) =
  ##Permute strs,lens to be in-maj-col width-sorted; May sound odd, but is
  ##useful for finding promising renames/deletes to get more rows in a listing.
  let ixes = sortByWidth(lens, m, nr, nc)
  var nStrs = newSeq[string](strs.len)
  var nLens = newSeq[int](lens.len)
  for i, ix in ixes:
    nStrs[m*i .. (m*i + m-1)] = strs[ix .. (ix + m-1)]
    nLens[m*i .. (m*i + m-1)] = lens[ix .. (ix + m-1)]
  strs = nStrs
  lens = nLens

const maxspc = 1023
const spaces = repeat(' ', maxspc + 1)
proc write*(f: File; strs: seq[string]; lens: seq[int]; ws: seq[int];
            m,nr,nc,widest: int; pfx: string) =
  ##Write lines to file w/padding; lens[i]<0 means left align else right align.
  let ncMaj = nc div m
  for r in 0 ..< min(nr, if widest > 0: widest else: nr):
    if pfx.len > 0: f.write pfx         #0,1..   nr*m,nr*m+1.. nr*2m,nr*2m+1..
    for mc in 0 ..< ncMaj:              #m,m+1.. add nr*m      add nr*m again
      for j in 0 ..< m:
        let k = r * m + nr * mc * m + j
        if k >= strs.len:
          break                         #Done with maybe short row
        let pad = abs(ws[mc*m + j]) - abs(lens[k])
        if lens[k] > 0 and pad > 0:
          f.write spaces[0 ..< pad]     #positive => left pad/right align
        f.write strs[k]
        if lens[k] <= 0 and pad > 0 and not (mc == ncMaj - 1 and j == m - 1):
          f.write spaces[0 ..< pad]     #zero/negative => right pad/left align
    f.write '\n'
