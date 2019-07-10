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

proc abbrev*(str, sep: string; mx, hd, tl: int): string {.inline.} =
  ## Abbreviate str as str[0..<hd], sep, str[^tl..^1] only if str.len > mx.
  if mx > 0 and str.len > mx:
    str[0 ..< hd] & sep & str[^tl .. ^1]
  else:
    str

proc parseAbbrevSetHdTl(mx, sLen: int; hd, tl: var int) {.inline.} =
  if hd == -1 and tl == -1:     #Both missing or auto: balanced tl-biased slice
    hd = (mx - sLen) div 2
    tl = (mx - sLen - hd)
  elif hd == -1: hd = max(0, mx - sLen - tl)  #Only missing one; set other to
  elif tl == -1: tl = max(0, mx - sLen - hd)  #..remaining or zero if none left
  hd = min(hd, mx - sLen)
  tl = min(tl, mx - sLen)

proc parseAbbrev*(s: string; mx: var int; sep: var string; hd, tl: var int) =
  ##Parse comma-separated abbreviation spec ``s`` into ``mx``, ``sep``, ``hd``,
  ##``tl``.  Non-numeric ``mx`` =>-1 => caller should re-invoke with correct mx.
  ##Non-numeric|missing ``hd`` => ``mx-sep.len-tl`` Non-numeric or missing
  ##``tl`` => ``mx-sep.len-hd``.  Non-num|missing both => ``hd=(mx-sep.len)/2;
  ##tl=mx-sep.len-hd`` (which gives ``tl`` 1 more for odd ``mx-sep.len``).
  if s.len == 0: return
  let cols = s.split(',')       #Leading/trailing whitespace in sep is used.
  if cols.len > 4: raise newException(ValueError, "bad abbrev spec: \""&s&"\"")
  sep = if cols.len > 3: cols[3] else: "*"
  if mx == 0: mx = parseInt(cols[0], -1)
  hd = if cols.len > 1: parseInt(cols[1], -1) else: -1
  tl = if cols.len > 2: parseInt(cols[2], -1) else: -1
  if mx == -1: return           #Caller should re-invoke w/actual max
  parseAbbrevSetHdTl(mx, sep.printedLen, hd, tl)

proc uniqueAbs(strs: openArray[string]; sep: string; mx, hd, tl: int): bool =
  ## return true only if ``mx``, ``hd``, ``tl`` yields a set of unique
  ## abbreviations for strs.
  var es = initHashSet[string]()
  for s in strs:                        #done when the first duplicate is seen
    if es.containsOrIncl(abbrev(s, sep, mx, hd, tl)): return false
  return true

proc smallestMaxSTUnique(strs: openArray[string]; mLen, sLen: int;
                         sep: string; hd, tl: var int): tuple[m, h, t: int] =
  var h2, t2: int
  var lo = sLen + 1                     #Binary search on [sLen+1, mLen] for
  var hi = mLen                         #..least result s.t. strs.uniqueAbs.
  while hi > lo:
    let m = (lo + hi) div 2
    h2 = hd; t2 = tl                    #Assign to temporaries, not return hd,tl
    parseAbbrevSetHdTl(m, sLen, h2, t2)
    if strs.uniqueAbs(sep, m, h2, t2): hi = m     #m => unique: bracket lower
    else: lo = m + 1                              #not unique: bracket higher
  parseAbbrevSetHdTl(lo, sLen, hd, tl)  #fix up derived values
  result = (lo, hd, tl)                 #Now lo == hi

proc smallestMaxSTUnique*(strs: openArray[string]; sep: string;
                          hd, tl: var int, optim=false): int =
  ## Semi-efficiently find the smallest max such that ``strs`` can be uniquely
  ## abbreviated by ``abbrev(s, mx, hd, tl)`` for all ``s`` in ``strs``.  If
  ## ``optim`` is true, ignore any specified ``hd,tl`` and find ``hd,tl`` that
  ## finds the minimum-minimum-maximum.
  var mLen: int
  for s in strs: mLen = max(mLen, s.len)
  let sLen = sep.printedLen
  if mLen <= sLen + 1:
    parseAbbrevSetHdTl(sLen + 1, sLen, hd, tl)
    return sLen + 1
  if optim:
    var res: seq[tuple[m, h, t: int]]
    for h in 0..mLen:
      var h2 = h; var t2 = -1
      res.add strs.smallestMaxSTUnique(mLen, sLen, sep, h2, t2)
    res.sort
    hd = res[0].h
    tl = res[0].t
    result = res[0].m
  else:
    result = strs.smallestMaxSTUnique(mLen, sLen, sep, hd, tl).m

proc smallestMaxSTUnique*[T](tab: Table[T, string]; sep: string;
                             hd, tl: var int, optim=false): int =
  ## Find smallest max s.t. abbrev unique over ``values`` of ``tab``.
  var strs: seq[string]
  for v in tab.values: strs.add v
  strs.smallestMaxSTUnique sep, hd, tl, optim

proc uniqueAbbrev*(strs: openArray[string]; sep: string; nWild=1): seq[string] =
  ## Return narrowest unique abbrevation set for ``strs`` given some number of
  ## wildcards (``sep``, probably ``*``), where both location and number of
  ## wildcards can vary from string to string.
  discard
