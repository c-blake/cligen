## This module defines MSlice - basically a non-garbage-collected ``string`` -
## and various utility iterators & procs for it such as ``mSlices``&``msplit``.
## There are basically 3 kinds of splitting - file-line-like, and then delimited
## by one byte, by a set of bytes (both either repeatable|not).  The latter two
## styles can also be bounded by a number of splits/number of outputs and accept
## either ``MSlice`` or ``string`` as inputs to produce the ``seq[MSlice]``.

type csize = uint
proc cmemchr*(s: pointer, c: char, n: csize): pointer {.
  importc: "memchr", header: "<string.h>" .}
proc cmemrchr*(s: pointer, c: char, n: csize): pointer {.
  importc: "memchr", header: "<string.h>" .}
proc cmemcmp*(a, b: pointer, n: csize): cint {. #Exported by system/ansi_c??
  importc: "memcmp", header: "<string.h>", noSideEffect.}
proc cmemcpy*(a, b: pointer, n: csize): cint {.
  importc: "memcpy", header: "<string.h>", noSideEffect.}
proc `-!`*(p, q: pointer): int {.inline.} =
  (cast[int](p) -% cast[int](q)).int
proc `+!`*(p: pointer, i: int): pointer {.inline.} =
  cast[pointer](cast[int](p) +% i)
proc `+!`*(p: pointer, i: uint64): pointer {.inline.} =
  cast[pointer](cast[uint64](p) + i)

type MSlice* = object
  ## Represent a memory slice, such as a delimited record in an ``MFile``.
  ## Care is required to access ``MSlice`` data (think C mem* not str*).
  ## toString to some (reusable?) string buffer for safer/compatible work.
  mem*: pointer
  len*: int

proc toMSlice*(a: string, keep=false): MSlice =
  ## Convert string to an MSlice.  If ``keep`` is true, a copy is allocated
  ## which may be freed via ``dealloc(result.mem)``.
  result.len = a.len
  if keep:
    let data = alloc0(a.len + 1)
    copyMem(data, a[0].unsafeAddr, a.len)
    result.mem = cast[cstring](data)
  else:
    result.mem = a.cstring

proc toCstr*(p: pointer): cstring {.inline.} =
  ## PROBABLY UNTERMINATED cstring.  BE VERY CAREFUL.
  cast[cstring](p)

proc `[]`*(ms: MSlice, i: int): char {.inline.} =
  ms.mem.toCstr[i]

proc toString*(ms: MSlice, s: var string) {.inline.} =
  ## Replace a Nim string ``s`` with data from an MSlice.
  s.setLen(ms.len)
  if ms.len > 0:
    copyMem(addr(s[0]), ms.mem, ms.len)

proc `$`*(ms: MSlice): string {.inline.} =
  ## Return a Nim string built from an MSlice.
  ms.toString(result)

proc add*(s: var string, ms: MSlice) {.inline.} =
  ## Append an `MSlice` to a Nim string
  if ms.len < 1: return
  let len0 = s.len
  s.setLen len0 + ms.len
  copyMem s[len0].addr, ms.mem, ms.len

proc `==`*(x, y: MSlice): bool {.inline.} =
  ## Compare a pair of MSlice for strict equality.
  x.len == y.len and equalMem(x.mem, y.mem, x.len)

proc `<`*(a,b: MSlice): bool {.inline.} =
  ## Compare a pair of MSlice for inequality.
  let c = cmemcmp(a.mem, b.mem, min(a.len, b.len).csize)
  if c == 0: a.len < b.len else: c < 0

proc write*(f: File, ms: MSlice) {.inline.} =
  ## Write ``ms`` data to file ``f``.
  discard writeBuffer(f, ms.mem, ms.len)

proc urite*(f: File, ms: MSlice) {.inline.} =
  ## unlocked write ``ms`` data to file ``f``.
  when defined(linux) and not defined(android):
    proc c_fwrite(buf: pointer, size, n: csize, f: File): cint {.
            importc: "fwrite_unlocked", header: "<stdio.h>".}
  else:
    proc c_fwrite(buf: pointer, size, n: csize, f: File): cint {.
            importc: "fwrite", header: "<stdio.h>".}
  discard c_fwrite(ms.mem, 1, ms.len.csize, f)

proc mrite*(f: File, mses: varargs[MSlice]) {.inline.} =
  ## unlocked write all ``mses`` to file ``f``; Be careful of many fwrite()s.
  for ms in items(mses): f.urite ms

proc `==`*(a: string, ms: MSlice): bool {.inline.} =
  a.len == ms.len and cmemcmp(unsafeAddr a[0], ms.mem, a.len.csize) == 0
proc `==`*(ms: MSlice, b: string): bool {.inline.} = b == ms

import std/hashes # hashData
proc hash*(ms: MSlice): Hash {.inline.} =
  ## hash MSlice data; With ``==`` all we need to put in a Table/Set
  result = hashData(ms.mem, ms.len)

iterator mSlices*(mslc: MSlice, sep=' ', eat='\0'): MSlice =
  ## Iterate over [optionally ``eat``-suffixed] ``sep``-delimited slices in
  ## ``mslc``.  Delimiters are NOT part of returned slices.  Pass eat='\\0' to
  ## be strictly `sep`-delimited.  A final, unterminated record is returned
  ## like any other.  You can swap ``sep`` & ``eat`` to ignore any optional
  ## prefix except '\\0'.  This is similar to "lines parsing".  E.g. usage:
  ##
  ## .. code-block:: nim
  ##   import mfile; var count = 0  #Count initial '#' comment lines
  ##   for slice in mSlices(mopen("foo").toMSlice):
  ##     if slice.len > 0 and slice[0] != '#': count.inc
  if mslc.mem != nil:
    var ms = MSlice(mem: mslc.mem, len: 0)
    var remaining = mslc.len
    while remaining > 0:
      let recEnd = cmemchr(ms.mem, sep, remaining.csize)
      if recEnd == nil:                             #Unterminated final slice
        ms.len = remaining                          #Weird case..consult eat?
        yield ms
        break
      ms.len = recEnd -! ms.mem                     #sep is NOT included
      if eat != '\0' and ms.len > 0 and ms[ms.len - 1] == eat:
        dec(ms.len)                                 #trim pre-sep char
      yield ms
      ms.mem = recEnd +! 1                          #skip sep
      remaining = mslc.len - (ms.mem -! mslc.mem)

proc msplit*(mslc: MSlice, fs: var seq[MSlice], sep=' ', eat='\0') =
  ## Use ``mslices`` iterator to populate fields ``seq[MSlice] fs``.
  var n = 0
  var nA = 16
  fs.setLen(nA)
  for ms in mSlices(mslc, sep):
    if n + 1 > nA:
      nA = if nA < 512: 2*nA else: nA + 512
      fs.setLen(nA)
    fs[n] = ms
    inc(n)
  fs.setLen(n)

const wspace* = {' ', '\t', '\v', '\r', '\l', '\f'}  ## == strutils.Whitespace

proc charEq(x, c: char): bool {.inline.} = x == c

proc charIn(x: char, c: set[char]): bool {.inline.} = x in c

proc mempbrk*(s: pointer, accept: set[char], n: csize): pointer {.inline.} =
  for i in 0 ..< int(n):  #Like cstrpbrk or cmemchr but for mem
    if (cast[cstring](s))[i] in accept: return s +! i

proc mem(s: string): pointer = cast[pointer](cstring(s))

template defSplit[T](slc: T, fs: var seq[MSlice], n: int, repeat: bool,
                     sep: untyped, nextSep: untyped, isSep: untyped) {.dirty.} =
  fs.setLen(if n < 1: 16 else: n)
  var b   = slc.mem
  var eob = b +! slc.len
  while repeat and eob -! b > 0 and isSep((cast[cstring](b))[0], sep):
    b = b +! 1
    if b == eob: fs.setLen(0); return
  var e = nextSep(b, sep, (eob -! b).csize)
  while e != nil:
    if n < 1:                               #Unbounded msplit
      if result == fs.len - 1:              #Expand capacity
        fs.setLen(if fs.len < 512: 2*fs.len else: fs.len + 512)
    elif result == n - 1:                   #Need 1 more slot for final field
      break
    fs[result].mem = b
    fs[result].len = e -! b
    result += 1
    while repeat and eob -! e > 0 and isSep((cast[cstring](e))[1], sep):
      e = e +! 1
    b = e +! 1
    if eob -! b <= 0:
      b = eob
      break
    e = nextSep(b, sep, (eob -! b).csize)
  if not repeat or eob -! b > 0:
    fs[result].mem = b
    fs[result].len = eob -! b
    result += 1
  fs.setLen(result)

proc msplit*(s: MSlice, fs: var seq[MSlice], sep=' ', n=0, repeat=false):int=
  defSplit(s, fs, n, repeat, sep, cmemchr, charEq)

proc msplit*(s: MSlice, sep=' ', n=0, repeat=false): seq[MSlice] {.inline.} =
  discard msplit(s, result, sep, n, repeat)

proc msplit*(s: MSlice, fs: var seq[MSlice], seps=wspace, n=0, repeat=true):int=
  defSplit(s, fs, n, repeat, seps, mempbrk, charIn)

proc msplit*(s: MSlice, n=0, seps=wspace, repeat=true): seq[MSlice] {.inline.} =
  discard msplit(s, result, seps, n, repeat)

proc msplit*(s: string, fs: var seq[MSlice], sep=' ', n=0, repeat=false):int=
  ## msplit w/reused ``fs[]`` & bounded cols ``n``. ``discard msplit(..)``.
  defSplit(s, fs, n, repeat, sep, cmemchr, charEq)

proc msplit*(s: string, sep: char, n=0, repeat=false): seq[MSlice] {.inline.} =
  ##Like ``msplit(string, var seq[MSlice], int, char)``, but return the ``seq``.
  discard msplit(s, result, sep, n, repeat)

proc msplit*(s: string, fs: var seq[MSlice], seps=wspace, n=0, repeat=true):int=
  ## Fast msplit with cached fs[] and single-char-of-set delimiter. n >= 2.
  defSplit(s, fs, n, repeat, seps, mempbrk, charIn)

proc msplit*(s: string, seps=wspace, n=0, repeat=true): seq[MSlice] {.inline.}=
  discard msplit(s, result, seps, n, repeat)

template defSplitr(slc: string, fs: var seq[string], n: int, repeat: bool,
                   sep: untyped, nextSep: untyped, isSep: untyped,
                   sp: ptr seq[string]) {.dirty.} =
  fs.setLen(if n < 1: 16 else: n)
  if sp != nil: sp[].setLen fs.len
  var b0  = slc.mem
  var b   = b0
  var eob = b +! slc.len
  while repeat and eob -! b > 0 and isSep((cast[cstring](b))[0], sep):
    b = b +! 1
    if b == eob:
      fs.setLen(0)
      if sp != nil: sp[].setLen(0)
      return
  var e = nextSep(b, sep, (eob -! b).csize)
  while e != nil:
    if n < 1:                               #Unbounded splitr
      if result == fs.len - 1:              #Expand capacity
        fs.setLen(if fs.len < 512: 2*fs.len else: fs.len + 512)
        if sp != nil: sp[].setLen fs.len
    elif result == n - 1:                   #Need 1 more slot for final field
      break
    fs[result] = slc[(b -! b0) ..< (e -! b0)]
    result += 1
    let e0 = e
    while repeat and eob -! e > 0 and isSep((cast[cstring](e))[1], sep):
      e = e +! 1
    if sp != nil: sp[][result - 1] = slc[(e0 -! b0) .. (e -! b0)]
    b = e +! 1
    if eob -! b <= 0:
      b = eob
      break
    e = nextSep(b, sep, (eob -! b).csize)
  if not repeat or eob -! b > 0:
    fs[result] = slc[(b -! b0) ..< (eob -! b0)]
    if sp != nil: sp[][result] = ""
    result += 1
  fs.setLen(result)
  if sp != nil: sp[].setLen(result)

proc splitr*(s: string, fs: var seq[string], sep=' ', n=0, repeat=false,
             sp: ptr seq[string] = nil): int =
  ##split w/reused ``fs[]`` & bounded cols ``n``, maybe-repeatable sep.
  defSplitr(s, fs, n, repeat, sep, cmemchr, charEq, sp)

proc splitr*(s: string, sep: char, n=0, repeat=false): seq[string] {.inline.} =
  ##Like ``splitr(string, var seq[string], int, char)``, but return the ``seq``.
  discard splitr(s, result, sep, n, repeat)

proc splitr*(s: string, fs: var seq[string], seps=wspace, n=0, repeat=true,
             sp: ptr seq[string] = nil): int =
  ##split w/reused fs[], bounded cols char-of-set sep which can maybe repeat.
  defSplitr(s, fs, n, repeat, seps, mempbrk, charIn, sp)

proc splitr*(s: string, seps=wspace, n=0, repeat=true): seq[string] {.inline.}=
  ##Like ``splitr(string, var seq[string], int, set[char])``,but return ``seq``.
  discard splitr(s, result, seps, n, repeat)

type Splitr* = tuple[ repeat: bool, chrDlm: char, setDlm: set[char], n: int ]

proc initSplitr*(delim: string): Splitr =
  ##Abstract single-string hybrid specification of maybe-repeat-folding 1-char |
  ##maybe-repeat-folding char set delimiting.  Specifically, if ``delim`` chars
  ##are all the same, ``repeat=delim.len>1`` & delimiting is 1-char.  Else, if
  ##``delim`` chars vary, ``repeat=*ANY*dup``. Magic val ``"white"``=>repeated
  ##white space chars. Eg.: ``","``=strict CSV, ``"<SPC><SPC>"``=folding spaces
  ##``",:"``=strict comma-colon-separation, ",::"= repeat-folding common-colon.
  if delim == "white":          #User can use any other permutation if needed
    result.repeat = true
    result.chrDlm = ' '
    result.setDlm = wspace
    result.n      = wspace.card #=6 unless wspace defn changes
    return
  for c in delim:
    if c in result.setDlm:
      result.repeat = true
      continue
    result.setDlm.incl(c)
    inc(result.n)
  if result.n == 1:             #support n==1 test to allow memchr optimization
    result.chrDlm = delim[0]

proc split*(s: Splitr, line: MSlice, cols: var seq[MSlice], n=0) {.inline.} =
  if s.n > 1: discard msplit(line, cols, seps=s.setDlm, n, s.repeat)
  else      : discard msplit(line, cols, s.chrDlm     , n, s.repeat)

proc split*(s: Splitr, line: string, cols: var seq[string], n=0) {.inline.} =
  if s.n > 1: discard splitr(line, cols, seps=s.setDlm, n, s.repeat)
  else      : discard splitr(line, cols, s.chrDlm     , n, s.repeat)

proc split*(s: Splitr, line: string, n=0): seq[string] {.inline.} =
  s.split(line, result, n)

iterator items*(a: MSlice): char {.inline.} =
  ## Iterates over each char of `a`.
  for i in 0 ..< a.len:
    yield a[i]

proc findNot*(s: string, chars: set[char], start: Natural = 0, last = 0): int =
  ## Searches for *NOT* `chars` in `s` inside inclusive range ``start..last``.
  ## If `last` is unspecified, it defaults to `s.high` (the last element).
  ##
  ## If `s` contains none of the characters in `chars`, -1 is returned.
  ## Otherwise the index returned is relative to ``s[0]``, not ``start``.
  ## Use `s[start..last].find` for a ``start``-origin index.
  ##
  ## See also:
  ## * `rfind proc<#rfind,string,set[char],Natural,int>`_
  ## * `multiReplace proc<#multiReplace,string,varargs[]>`_
  let last = if last == 0: s.high else: last
  for i in int(start)..last:
    if s[i] notin chars: return i
  return -1

when isMainModule:  #Run tests with n<1, nCol, <nCol, repeat=false,true.
  let s = "1_2__3"
  let m = s.toMSlice
  for i in 0..5: echo i, " strict: ", m.msplit('_', i)
  echo ""
  for i in 0..4: echo i, " loose:: ", m.msplit('_', i, repeat=true)
  for i in 0..5:
    assert s.msplit('_', i) == m.msplit('_', i)
  for i in 0..4:
    assert s.msplit('_', i, repeat=true) == m.msplit('_', i, repeat=true)
  for i in 0..5:
    for j, ms in m.msplit('_', i):
      assert s.splitr('_', i)[j] == $ms
  for i in 0..5:
    for j, ms in m.msplit('_', i, repeat=true):
      assert s.splitr('_', i, repeat=true)[j] == $ms
  echo "1_2__3".splitr('_', repeat=true)
  echo "__1_2__3".splitr('_', repeat=true)
  echo "__1_2__3__".splitr('_', repeat=true)
  echo "___".splitr('_', repeat=true)
  echo "___1".splitr('_', repeat=true)
  echo "1___".splitr('_', repeat=true)
