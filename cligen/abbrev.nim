##This module is about construction of shell-`*` wildcard-like abbreviations for
##a set of strings.  The simplest variant is when the user gives us a specific
##maximum string length and at least one component of the head,tail slices.  In
##that case, `abbrev` just wraps Nim string slicing and the set of abbreviations
##may or may not uniquely cover the input string set.
##
##When the user leaves certain aspects automatic/undefined, various algorithms
##can be deployed to find optimized answers within various constraints.  The
##most important constraint is likely uniqueness.  Can I select a string, paste
##it into a shell REPL, and expect it to expand to exactly 1 item?  The same
##concept applies to non-filename strings, but there is less help from a shell
##to expand them.  Eg., 10-40 user names on a lightly configured single-user
##Unix system uses "a directory in your brain" (or you can write a small
##expander script to spot-check anything non-obvious in context).
##
##The simplest automatic setting is just a fixed wildcard spot protocol such as
##a specific head or mid-point with binary search quickly finding a smallest max
##limit which makes abbreviations unique.  Visually this results in columns of
##abbreviations where the wildcard `*`s line up vertically which seems easier to
##read.  We can also ignore user head,tail specs, instead finding the location
##that minimizes the width of the string set.  This code does that by just
##trying all possible locations.  This starts to be slow for a computer but
##remains fast for a human (eg. 400 ms on a directory of 12,000 entries).
##
##The next level of optimization/data compression is to allow the location of
##the wildcard to vary from string to string.  After that, allowing >1 '*' can
##continue to shorten strings.  Each optimization level removes more context
##making strings harder to read and probably gets slower to compute.  Efficient
##algorithms for this case are a work in progress.

import strutils, algorithm, sets, tables, ./tern, ./humanUt, ./textUt

type Abbrev* = object
  sep: string
  mx*, hd, tl, sLen, m, h, t: int
  optim: bool
  abbOf: Table[string, string]

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
  ##Parse comma-separated abbreviation spec [mx][,[hd][,[tl][,[sep]]]] ``s``
  ##into ``Abbrev abb``.  Non-numeric ``mx`` => -1 => caller must set mx and
  ##call ``update``.  Non-numeric|missing ``hd`` => ``mx-sep.len-tl``
  ##Non-numeric or missing ``tl`` => ``mx-sep.len-hd``.  Non-num|missing both =>
  ##``hd=(mx-sep.len)/2; tl=mx-sep.len-hd`` (which gives ``tl`` 1 more for odd
  ##``mx-sep.len``).  ``mx <=0`` => various locally optimized ``uniqueAbbrevs``.
  if s.len == 0: return
  let cols = s.split(',')       #Leading/trailing whitespace in sep is used.
  if cols.len > 4: raise newException(ValueError, "bad abbrev spec: \""&s&"\"")
  result.optim = s.startsWith("a")
  result.mx = if cols.len > 0: parseInt(cols[0], -1) else: -1
  result.hd = if cols.len > 1: parseInt(cols[1], -1) else: -1
  result.tl = if cols.len > 2: parseInt(cols[2], -1) else: -1
  result.sep = if cols.len > 3: cols[3] else: "*"
  result.sLen = result.sep.printedLen
  if result.mx != -1: result.update   #For -1 caller must call realize

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

proc width(strs: openArray[string]): float =
  if strs.len == 0: return 0
  var total = 0.0         #XXX placeholder.  It should become a "score" where
  for s in strs:          #high serial auto-correlation down-weights things
    total += s.len.float  #to get the most table cols (or maybe even run layout
  total / strs.len.float  #on the whole set and call total width score).

proc uniqueAbbrevs*(strs: openArray[string], nWild=1, sep="*"): seq[string] =
  ## Return narrowest unique abbrevation set for ``strs`` given some number of
  ## wildcards (``sep``, probably ``*``), where both location and number of
  ## wildcards can vary from string to string.
  if   nWild == -2: result = strs.uniquePfxPats(sep)  #Simplest patterns
  elif nWild == -3: result = strs.uniqueSfxPats(sep)
  elif nWild == -4:                     #whichever is globally narrower
    let pfx = strs.uniquePfxPats(sep)
    let sfx = strs.uniqueSfxPats(sep)
    result = if pfx.width < sfx.width: pfx else: sfx
  elif nWild == -5:                     #whichever is locally narrower
    result.setLen strs.len
    let pfx = strs.uniquePfxPats(sep)   #XXX May sacrifice uniqueness guarantee,
    let sfx = strs.uniqueSfxPats(sep)   #..but I cannot find counter example.
    for i in 0 ..< strs.len:
      result[i] = if pfx[i].len < sfx[i].len: pfx[i] else: sfx[i]
# elif nWild == -6:                     #best locally varying 1-* pattern
# elif nWild == -7:                     #best locally varying 2-* pattern
# elif nWild == -8:                     #best locally varying 3-* pattern
# elif nWild == -9:                     #best locally varying 4-* pattern

proc realize*(a: var Abbrev, strs: openArray[string]) =
  ## Semi-efficiently find the smallest max such that ``strs`` can be uniquely
  ## abbreviated by ``abbrev(s, mx, hd, tl)`` for all ``s`` in ``strs``.
  a.update
  var mLen: int
  for s in strs: mLen = max(mLen, s.len)
  if mLen <= a.sLen + 1:
    a.mx = a.sLen + 1; a.update
    return
  if a.mx < -1:
    for i, abb in uniqueAbbrevs(strs, a.mx, a.sep):
      a.abbOf[strs[i]] = abb
  elif a.optim:
    var res: seq[tuple[m, h, t: int]]
    for h in 0..mLen:
      var a2 = a; a2.hd = h; a2.tl = -1
      a2.minMaxSTUnique(strs, mLen)
      res.add (a2.m, a2.h, a2.t)
    res.sort
    a.hd = res[0].h; a.tl = res[0].t; a.mx = res[0].m
    a.update
  else:
    a.minMaxSTUnique(strs, mLen)

proc realize*[T](a: var Abbrev, tab: Table[T, string]) =
  ## Find smallest max s.t. abbrev unique over ``values`` of ``tab``.
  if tab.len == 0 or a.mx >= 0: return
  var strs: seq[string]
  for v in tab.values: strs.add v
  a.realize strs

when isMainModule:
  proc abb(abbr="", byLen=false, strs: seq[string]) =
    var a = parseAbbrev(abbr)
    a.realize strs
    if byLen:
      var sq: seq[string]
      for s in strs: sq.add a.abbrev s
      sq.sort(proc(a, b: string): int = cmp(a.len, b.len))
      for s in sq: echo s
    else:
      for s in strs: echo a.abbrev s
  import ../cligen; dispatch abb
