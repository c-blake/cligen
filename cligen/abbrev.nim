##This module is about construction of shell-`*` wildcard abbreviations for a
##set of strings.  The simplest variant is when the user gives us a specific
##maximum string length and at least one component of the head,tail slice.  In
##that case, `abbrev` just wraps Nim string slicing and the set of abbreviations
##may or may not uniquely cover the input string set.
##
##When the user leaves certain aspects automatic/undefined, various algorithms
##can be deployed with various constraints to find optimized answers.  The most
##important constraint in my mind is uniqueness.  Can I select a string, paste
##it into a shell REPL, and expand it to a single item when CWD=directory of the
##file name.  The same concept still applies to non-filename strings, but there
##is no help from a shell.  Eg., the 10-40 usernames on a lightly configured
##single-user Unix system may roughly be "in a directory in your brain".
##
##The simplest automatic setting is just a fixed wildcard spot protocol with
##binary search quickly finding a smallest max limit which makes abbreviations
##unique.  We can still let the user specify a head or tail in such situations.
##Visually this results in columns of abbreviations where the wildcard `*`s line
##up vertically which is quite easy to read, at least for me.  We can also not
##let the user fix head,tail, but find the location that minimizes the width of
##the string set.  This code does that by just trying all possible locations.
##This starts to be slow for a computer but remains fast for a human (eg. 400 ms
##on a directory of 12,000 entries).
##
##The next level of optimization/data compression is to allow the location of
##the wildcard to vary from string to string.  After that, allowing >1 '*' is
##the only way to continue to shorten strings.  Each optimization level obscures
##more of the strings in output, and probably gets slower to compute.  At higher
##varying wildcard location/number levels, the API must be to return the entire
##set of abbreviations since they share no alignments.  Efficient algorithms for
##this case are a work in progress.

import strutils, algorithm, sets, tables, ./humanUt, ./textUt

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

proc realize*(a: var Abbrev, strs: openArray[string]) =
  ## Semi-efficiently find the smallest max such that ``strs`` can be uniquely
  ## abbreviated by ``abbrev(s, mx, hd, tl)`` for all ``s`` in ``strs``.
  a.update
  var mLen: int
  for s in strs: mLen = max(mLen, s.len)
  if mLen <= a.sLen + 1:
    a.mx = a.sLen + 1; a.update
    return
  if a.optim:
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

proc uniqueAbbrev*(strs: openArray[string]; sep: string; nWild=1): seq[string] =
  ## Return narrowest unique abbrevation set for ``strs`` given some number of
  ## wildcards (``sep``, probably ``*``), where both location and number of
  ## wildcards can vary from string to string.
  discard
when isMainModule:
  proc abb(abbr="", byLen=false, strs: seq[string]) =
    var a = parseAbbrev(abbr)
    a.realize strs
    if byLen:
      var sq: seq[string]
      for s in strs: sq.add a.abbrev s
      sq.sort(proc(a, b: string): int = cmp(a.len, b.len))
      for s in sq: echo a.abbrev s
    else:
      for s in strs: echo a.abbrev s
  import cligen; dispatch abb
