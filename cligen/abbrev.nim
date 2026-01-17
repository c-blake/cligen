##[ This module is about building shell-`*` wildcard abbreviations for sets of
strings.  The simplest variant is when the user gives a specific maximum string
length and at least one component of the head,tail slice amounts.  In that case,
`abbrev` just wraps Nim string slicing BUT the set of abbreviations may NOT
UNIQUELY EXPAND within the input string set.

When users leave certain aspects automatic/undefined, various algorithms can be
deployed to find optimized answers within various constraints.  The likely most
important constraint is uniqueness.  Can one copy-paste strings into shell REPLs
and expect each to expand to exactly 1 item?  The same concept applies to
non-filename strings, but there is less help from shells to auto-expand.  Eg.,
10-40 user names on a lightly configured single-user Unix system might expand
using "a directory in your brain" (or you can write a small expander script to
spot-check anything non-obvious in context).

The simplest automatic setting is a fixed wildcard position protocol such as a
specific head or mid-point with binary search quickly finding a smallest max
limit which makes abbreviations unique.  Visually this results in columns of
abbreviations where the wildcard `*`s line up vertically which seems easier to
read and is most similar to an ellipsis (...) separator the NeXT cube file
browser used.

As a next level of terminal-space optimization, we can ignore user head,tail
specs, instead finding the location that minimizes each width of the string set.
This code does that by just trying all possible locations for '*'.  This starts
to be a lot of brute force work and slow for a computer but remains fast for a
human (eg. sub-second for a directory of 18,000 entries).  (This is 'a' mode.)

The next level of optimization/data compression is to allow the location of the
wildcard to *vary from string to string* (shortest prefix or suffix or shorter
of both or best single-'*' location).  After that, allowing >1 '*' can continue
to shorten strings.  Each optimization level removes more context making strings
harder to read & gets slower to compute.  Meanwhile, tabular contexts often
decide (after initial lengths are known) padding space to align text visually.
That space can be repurposed to partially expand patterns which then eases
reading without loss of terminal rows which here we call `expandFit`.

Algo research here seems neglected.  The closest I could find is Minimal
Distinguishing Subsequence Patterns by Ji, Bailey & Dong in 2007 in a
bioinformatics context. ]##

when not declared Thread: import std/typedthreads
import std/[strutils, algorithm, sets, tables, math, osproc],
       ./[tern, humanUt, textUt, sysUt]

type Abbrev* = object
  sep: string
  qmark: char
  cset: set[char]
  mx*, hd, tl, sLen, m, h, t: int
  optim: bool
  abbOf: Table[string, string]
  all: Tern[void]

proc isAbstract*(a: Abbrev): bool {.inline.} =
  a.mx < 0 or a.hd < 0 or a.tl < 0

proc update*(a: var Abbrev) {.inline.} =
  ##Call this after any change to ``a.mx`` to update derived quantities.
  a.m = a.mx; a.h = a.hd; a.t = a.tl
  if not a.isAbstract: return
  if a.hd == -1 and a.tl == -1:     #Both missing|auto: balanced tl-biased slice
    a.h = (a.m - a.sLen) div 2
    a.t = (a.m - a.sLen - a.h)
  elif a.hd == -1: a.h = max(0, a.m - a.sLen - a.t) #Only missing 1; set oth to
  elif a.tl == -1: a.t = max(0, a.m - a.sLen - a.h) #..remaining|0 if none left
  a.h = min(a.h, a.m - a.sLen)
  a.t = min(a.t, a.m - a.sLen)

proc abbrev*(a: Abbrev, str: string): string {.inline.} =
  ## Abbreviate ``str`` as ``str[0..<hd], sep, str[^tl..^1]`` only if
  ## ``str.len > mx``.
  if a.abbOf.len > 0: return a.abbOf[str]
  if a.m > 0 and str.len > a.m:
    str[0 ..< a.h] & a.sep & str[^a.t .. ^1]
  else:
    str

proc parseAbbrev*(s: string): Abbrev =
  ##Parse comma-separated abbreviation spec `[mx][,[hd][,[tl][,[sep]]]] s`
  ##into ``Abbrev abb``.  Non-numeric ``mx`` => -1 => caller must set mx and
  ##call ``update``.  Non-numeric|missing ``hd`` => ``mx-sep.len-tl``
  ##Non-numeric or missing ``tl`` => ``mx-sep.len-hd``.  Non-num|missing both =>
  ##``hd=(mx-sep.len)/2; tl=mx-sep.len-hd`` (which gives ``tl`` 1 more for odd
  ##``mx-sep.len``).  ``mx < 0`` => various locally optimized ``uniqueAbbrevs``.
  if s.len == 0: result.sep = "*"; result.sLen = 1; return
  let cols = s.split(',')       #Leading/trailing whitespace in sep is used.
  if cols.len > 5: raise newException(ValueError, "bad abbrev spec: \""&s&"\"")
  result.optim = s.startsWith("a")
  result.mx = if cols.len > 0: parseInt(cols[0], -1) else: -1
  result.hd = if cols.len > 1: parseInt(cols[1], -1) else: -1
  result.tl = if cols.len > 2: parseInt(cols[2], -1) else: -1
  result.sep = if cols.len > 3: cols[3] else: "*"
  result.sLen = result.sep.printedLen
  if cols.len > 4:
    result.qmark = if cols[4].len > 0: cols[4][0] else: '\0'
    result.cset  = if cols[4].len > 1: toSetChar(cols[4][1..^1], true) else: {}
  if result.mx != -1: result.update   #For -1 caller must call realize

const parseAbbrevHelp* = """a\*|M,head(M/2),tail(M-hdSep),sep(\*),?chars
a:bestPos -2:pfx -3:sfx -4:mfx -5:1\* -6:2\*
POSITIVE_NUMBER=thatWidth/head/tail"""

proc uniqueAbs(a: Abbrev, strs: openArray[string]): bool =
  ## Return true only if ``a`` yields a set of unique abbreviations for strs.
  var es = initHashSet[string]()
  for s in strs:                        #done when the first duplicate is seen
    if es.containsOrIncl(a.abbrev s): return false
  return true

proc minMaxSTUnique(a: var Abbrev, strs: openArray[string], ml: int) =
  var a2 = a
  var lo = a.sLen + 1                   #Binary search on [a.sLen+1, ml] for
  var hi = ml                           #..least result s.t. a.uniqueAbs(strs).
  while hi > lo:
    a2.mx = (lo + hi) div 2; a2.update  #mid point
    if a2.uniqueAbs(strs): hi = a2.mx   #mid => unique: bracket lower
    else: lo = a2.mx + 1                #not unique: bracket higher
  a.mx = lo; a.update                   #Now lo == hi; set mx & update derived

#NOTE: Pattern "escape" cannot be independent of pattern compression because the
# wildcard ?/qmark is more general than any one char and may have been critical
# to distinguish compression uniqueness.  So, this escaping is best effort only.
proc pquote(a: Abbrev; abb: string): string =
  result = abb
  if a.cset.len < 1:
    return
  let star = if a.sep.len > 0: '*' else: '\0'
  var start = 0
  while start < result.len:
    let j = result.find(a.cset, start)
    if j < 0: break
    let old = result[j]
    result[j] = a.qmark
    if a.all.match(result, 2, a.qmark, star).len > 1:
      result[j] = old
    start = j + 1

proc parts(n,m:int):seq[Slice[int]]= #Split 0..<n into m subslices so that non-0
  var start = 0                      #..remains spread evenly over early slices.
  let (q, r)=(n div m, n mod m) # Quotient & Remainder
  for i in 0 ..< m:
    let size = if i < r: q + 1 else: q
    result.add start ..< (start + size)
    start += size

type TA = tuple[sep:ptr string,t:ptr Tern[void],sl:ptr Slice[int],st:pua string,
                pO: ptr seq[string]]    # Need threads not procs to be able to..
                                        #..just write into carried over result.
proc add(o: var string, s: string; a, b: int) =
  if b > a:
    let oL0 = o.len; o.setLen oL0 + b - a; copyMem o[oL0].addr, s[a].addr, b - a

proc w5(ta: TA) {.thread.} =            # TA = Thread Arg
  let (sep, t, sl, strs) = (ta.sep[], ta.t[], ta.sl[], ta.st)
  let sLen = sep.len; template R: untyped = ta.pO[]
  var pat = newString(256)
  for i in sl:                          # Try to improve with shortest any-spot
   if R[i].len - sLen > 1:              # Long enough to abbreviate more
    block outermost:                    # Simple but slow algo: Start
     let s = strs[i]
     for tLen in sLen + 1 ..< R[i].len: # From shortest possible pats, try all..
       for nSfx in 0 ..< tLen - sLen:   #..splits, stop when first unique found.
         let nPfx = tLen - sLen - nSfx
#        let pat = s[0 ..< nPfx] & sep & s[^nSfx .. ^1]
         pat.setLen 0; pat.add s,0,nPfx; pat.add sep; pat.add s,s.len-nSfx,s.len
         if pat.len < R[i].len and t.match(pat, 2, aN=sep[0]).len == 1:
           R[i].setLen pat.len; copyMem R[i][0].addr, pat[0].addr, pat.len
           break outermost              # Stop @shortest pattern w/unique match

proc w6(ta: TA) {.thread.} =            # TA = Thread Arg
  let (sep, t, sl, strs) = (ta.sep[], ta.t[], ta.sl[], ta.st)
  let sLen = sep.len; template R: untyped = ta.pO[]
  var pat = newString(256); var pfx = newString(256); var sfx = newString(256)
  for i in sl:                          # Try to improve with a second *
    if R[i].len - 2*sLen > 1:           # Long enough for more *s to help
      block outermost:                  # Like above but pfx*middle*sfx
        let s = strs[i]
        for tLen in 2*sLen+1 ..< R[i].len: #NOTE: "" middle is unhelpful
          for nSfx in 0 ..< tLen - 2*sLen:
            sfx.setLen 0; sfx.add s, s.len - nSfx, s.len
            for nPfx in 0 ..< tLen - nSfx - 2*sLen: # nPfx&nSfx lens fix data..
              pfx.setLen 0; pfx.add s, 0, nPfx      #..but mid can be ANY SUBSTR
              for nMid in 1 .. tLen - 2*sLen - nSfx - nPfx:
                for off in 0 .. s.len - nPfx - nSfx - nMid:
#                 let pat=pfx & sep & s[nPfx+off ..< nPfx+off+nMid] & sep & sfx
                  pat.setLen 0; pat.add pfx; pat.add sep
                  pat.add s, nPfx+off, nPfx+off+nMid
                  pat.add sep; pat.add sfx
                  if pat.len < R[i].len and t.match(pat, 2, aN=sep[0]).len == 1:
                    R[i].setLen pat.len;copyMem R[i][0].addr,pat[0].addr,pat.len
                    break outermost # stop at shortest pattern with unique match
import std/times
proc uniqueAbbrevs*(a: var Abbrev; strs: openArray[string], jobs=1, jobsN=150):
        seq[string] =
  ## Return narrowest unique abbrevation set for ``strs`` given some number of
  ## wildcards (``sep``, probably ``*``), where both location and number of
  ## wildcards can vary from string to string.
  let sep = a.sep; let n = strs.len
  let sLen = sep.len                    # Code below assumes 1/sep[0] in spots
  if n == 1: return @[(if sLen < strs[0].len: sep else: strs[0])] # best=just *
  if a.mx != -3: a.all = strs.toTern    # A TernaryST with all strings
  if   a.mx == -2: return a.all.uniquePfxPats(strs, sep)  # Simplest patterns
  elif a.mx == -3: return strs.uniqueSfxPats(sep)
  result.setLen n; let t = a.all        # <=-4: result->LOCALLY lesser of [ps]fx
  let pfx = t.uniquePfxPats(strs, sep)  # Because either individually guaranteed
  let sfx = strs.uniqueSfxPats(sep)     #..1 match in dir, we can mix & match &
  for i in 0 ..< n:                     #..not alter that guarantee.
    result[i] = if sfx[i].len < pfx[i].len: sfx[i] else: pfx[i]
  if a.mx == -4: return                 # Only best pfx|sfx requested; Done
  let pts = n.parts(if n < jobsN: 1 elif jobs > 0: jobs else: countProcessors())
  if pts.len > 1:
    var th = newSeq[Thread[TA]](pts.len)
    for i in 0 ..< th.len:
      th[i].createThread w5,(sep.addr,t.addr,pts[i].addr,strs.toPua,result.addr)
    joinThreads th
  else: (var all=0..<n; w5 (sep.addr,t.addr,all.addr, strs.toPua, result.addr))
  if a.mx == -5: return                 # Only best 1-* requested; Done
  if pts.len > 1:
    var th = newSeq[Thread[TA]](pts.len)
    for i in 0 ..< th.len:
      th[i].createThread w6,(sep.addr,t.addr,pts[i].addr,strs.toPua,result.addr)
    joinThreads th
  else: (var all=0..<n; w6 (sep.addr,t.addr,all.addr, strs.toPua, result.addr))

proc realize*(a: var Abbrev, strs: openArray[string], jobs=1, jobsN=150) =
  ## Semi-efficiently find the smallest max such that ``strs`` can be uniquely
  ## abbreviated by ``abbrev(s, mx, hd, tl)`` for all ``s`` in ``strs``.
  a.update
  var mLen: int
  for s in strs: mLen = max(mLen, s.len)
  if mLen <= a.sLen + 1 and a.mx >= -1:
    a.mx = a.sLen + 1; a.update
    return
  if a.mx < -1:
    for i, abb in a.uniqueAbbrevs(strs, jobs, jobsN):
      if a.mx == -3 and a.all.len < 1: a.all = strs.toTern #-3 doesn't set a.all
      a.abbOf[strs[i]] = a.pquote(abb)
  elif a.optim:
    var res: seq[tuple[m, h, t: int]]
    for h in 0..mLen:
      var a2 = a; a2.hd = h; a2.tl = -1
      a2.minMaxSTUnique(strs, mLen)
      res.add (a2.m, a2.h, a2.t)
    res.sort
    a.hd = res[0].h; a.tl = res[0].t; a.mx = res[0].m
    a.update
  elif a.mx == -1:
    a.minMaxSTUnique(strs, mLen)

proc realize*[T](a: var Abbrev, tab: Table[T, string], jobs=1, jobsN=150) =
  ## Find smallest max s.t. abbrev unique over ``values`` of ``tab``.
  if tab.len == 0 or a.mx >= 0: return
  var strs: seq[string]
  for v in tab.values: strs.add v
  a.realize strs, jobs, jobsN

proc sepExt(loc: var int; sep, abb, src: string): int =   #extent of sep
  loc = abb.find(sep)
  if loc < 0: return 0
  let nx = abb.find(sep, loc + 1)
  if nx < 0: return src.len - abb.len + sep.len
  return src[loc..^1].find abb[loc + 1 ..< nx]

proc sepExp(pat, src, sep: string; expBy: int; ext, loc: var int): string =
  if ext <= sep.len + expBy:      #1st sep saves no space in widened
    result = if loc + ext < src.len - 1:
               pat[0 .. loc-1] & src[loc .. loc + ext] & pat[loc+sep.len+1..^1]
             else:
               pat[0 .. loc-1] & src[loc .. ^1]
    ext = sepExt(loc, sep, result, src)
  else:
    result = pat[0 .. loc-1] & src[loc .. loc+expBy-1] & sep & pat[loc+1..^1]
    loc.inc expBy
    ext.dec expBy

proc expandFit*(a: var Abbrev; strs: var seq[string];
                ab0, ab1, wids, colWs: var seq[int]; w,jP,m,nr,nc: int) =
  ## Expand any ``a.sep`` in ``strs[m*i + jP][ab0[i] ..< ab1[i]]``, updating
  ## ``colWs[m*(i div nr) + jP]`` until all seps gone or ``colWs.sum==w``.
  ## I.e. ``colWs`` include gap to right.  Overall table structure is preserved.
  ## Early ``a.sep`` instances are fully expanded before later instances change.
  template expandBy(amt: int) {.dirty.} =
    pat = sepExp(pat, src[si], a.sep, amt, ext[si], loc[si])
    strs[ti] = strs[ti][0 ..< ab0[si]] & pat & strs[ti][ab1[si]..^1]
    a.abbOf[src[si][0..^1]] = pat[0..^1] #COPY
    wids[m*si+jP] = wids[m*si+jP].sgn * (wids[m*si+jP].abs + amt) #Fix rend wids
    ab1[si].inc amt                                 #Fix Abbrev Bracket/Slice

  var src = newSeq[string](ab0.len)
  var loc = newSeq[int](ab0.len)
  var ext = newSeq[int](ab0.len)
  var invMap: Table[string, string]
  for k,v in a.abbOf: invMap[v] = k
  for j in 0 ..< nc div m:
    let adjust = if j < nc div m - 1: -1 else: 0  #XXX `-gap`
    for i in 0 ..< nr:
      let si  = nr*j + i; let ti = m*si + jP  #Index for wids[] & strs[]
      if ti >= wids.len: break
      var pat = strs[ti][ab0[si] ..< ab1[si]]
      src[si] = if pat.len > 0: invMap[pat] else: ""  #XXX why ab0==ab1 => ""?
      ext[si] = sepExt(loc[si], a.sep, pat, src[si])
      while true:             #colW may be large enough to expand multiple seps
        if loc[si] < 0: break
        let xtra = colWs[m*j+jP] - wids[m*si+jP].abs + adjust
        if xtra <= 0: break
        let expBy = min(xtra, ext[si] - a.sep.len)
        expandBy expBy                  #Updates pat,strs[ti],wids[si],ab1[si]
  var anySep = true
  while anySep and colWs.sum < w:
    anySep = false
    for j in 0 ..< nc div m:
      var expanded = false
      for i in 0 ..< nr:
        let si  = nr*j + i; let ti = m*si + jP  #Index for wids[] & strs[]
        if ti >= wids.len: break
        if loc[si] < 0: continue        #No sep; skip to next pat
        anySep = true
        expanded = true
        var pat = strs[ti][ab0[si] ..< ab1[si]]
        expandBy 1                      #Updates pat,strs[ti],wids[si],ab1[si]
      if expanded:
        colWs[m*j + jP].inc
        if colWs.sum == w:
          if a.cset.len > 0:            #Re-quote expansion
            for j in 0 ..< nc div m:
              for i in 0 ..< nr:
                let si  = nr*j + i; let ti = m*si + jP
                if ti >= wids.len: break
                let abb = a.abbOf[src[si]]
                let quo = a.pquote(abb)
                if quo != abb:
                  strs[ti] = strs[ti][0..<ab0[si]] & quo & strs[ti][ab1[si]..^1]
                  a.abbOf[src[si][0..^1]] = strs[ti][0..^1] #COPY
          return

#UniqChk: abbrev -a-4 * | while {read p} {m=(${~p}); [ ${#m} == 1 ]||echo "$p"}
when isMainModule:
  proc abb(abbr="", byLen=false, jobs=1, jobsN=150, strs: seq[string]) =
    var a = parseAbbrev(abbr)  
    a.realize strs, jobs, jobsN
    if byLen:
      var sq: seq[string]
      for s in strs: sq.add a.abbrev s
      sq.sort(proc(a, b: string): int = cmp(a.len, b.len))
      for s in sq: echo s
    else:
      for s in strs: echo a.abbrev s
  import ../cligen; dispatch abb
