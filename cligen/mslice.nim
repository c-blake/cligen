## This module defines MSlice - basically a non-garbage-collected ``string`` -
## and various utility iterators & procs for it such as ``mSlices``&``msplit``.
## There are basically 3 kinds of splitting - file-line-like, and then delimited
## by one byte, by a set of bytes (both either repeatable|not).  The latter two
## styles can also be bounded by a number of splits/number of outputs and accept
## either ``MSlice`` or ``string`` as inputs to produce the ``seq[MSlice]``.

proc cmemchr*(s: pointer, c: char, n: csize): pointer {.
  importc: "memchr", header: "<string.h>" .}
proc cmemrchr*(s: pointer, c: char, n: csize): pointer {.
  importc: "memchr", header: "<string.h>" .}
proc cmemcmp*(a, b: pointer, n: csize): cint {. #Exported by system/ansi_c??
  importc: "memcmp", header: "<string.h>", noSideEffect.}
proc `-!`*(p, q: pointer): int {.inline.} =
  cast[int](p) -% cast[int](q)
proc `+!`*(p: pointer, i: int): pointer {.inline.} =
  cast[pointer](cast[int](p) +% i)

type MSlice* = object
  ## Represent a memory slice, such as a delimited record in an ``MFile``.
  ## Care is required to access ``MSlice`` data (think C mem* not str*).
  ## toString to some (reusable?) string buffer for safer/compatible work.
  mem*: pointer
  len*: int

proc toMSlice*(a: string): MSlice =  #I'd prefer to call this MSlice, but if I
  result.mem = a.cstring             #do here I get an already-defined error.
  result.len = a.len                 #(Works in another module, though.)

proc toCstr*(p: pointer): cstring =
  ## PROBABLY UNTERMINATED cstring.  BE VERY CAREFUL.
  cast[cstring](p)

proc toString*(ms: MSlice, s: var string) {.inline.} =
  ## Replace a Nim string ``s`` with data from an MSlice.
  s.setLen(ms.len)
  if ms.len > 0:
    copyMem(addr(s[0]), ms.mem, ms.len)

proc `$`*(ms: MSlice): string {.inline.} =
  ## Return a Nim string built from an MSlice.
  ms.toString(result)

proc `==`*(x, y: MSlice): bool {.inline.} =
  ## Compare a pair of MSlice for strict equality.
  result = (x.len == y.len and equalMem(x.mem, y.mem, x.len))

proc `<`*(a,b: MSlice): bool {.inline.} =
  ## Compare a pair of MSlice for inequality.
  cmemcmp(a.mem, b.mem, min(a.len, b.len)) < 0

proc write*(f: File, ms: MSlice) {.inline.} =
  ## Write ``ms`` datat to file ``f``.
  discard writeBuffer(f, ms.mem, ms.len)

proc `==`*(a: string, ms: MSlice): bool {.inline.} =
  a.len == ms.len and cmemcmp(unsafeAddr a[0], ms.mem, a.len) == 0
proc `==`*(ms: MSlice, b: string): bool {.inline.} = b == ms

import hashes # hashData
proc hash*(ms: MSlice): Hash {.inline.} =
  ## hash MSlice data; With ``==`` all we need to put in a Table/Set
  result = hashData(ms.mem, ms.len)

iterator mSlices*(mslc: MSlice, sep=' ', eat='\0'): MSlice =
  ## Iterate over [optionally ``eat`` suffixed] ``sep``-delimited slices in
  ## ``mslc``.  Delimiters are NOT part of returned slices.  Pass eat='\\0' to
  ## be strictly `sep`-delimited.  A final, unterminated record is returned
  ## like any other.  You can swap ``sep`` & ``eat`` to ignore any optional
  ## prefix except '\\0'.  This is similar to "lines parsing".  E.g.:
  ##
  ## .. code-block:: nim
  ##   import mfile; var count = 0  #Count initial '#' comment lines
  ##   for slice in mSlices(mopen("foo").toMSlice):
  ##     if slice.len > 0 and slice.mem.toCstr[0] != '#': count.inc
  if mslc.mem != nil:
    var ms = MSlice(mem: mslc.mem, len: 0)
    var remaining = mslc.len
    while remaining > 0:
      let recEnd = cmemchr(ms.mem, sep, remaining)
      if recEnd == nil:                             #Unterminated final slice
        ms.len = remaining                          #Weird case..consult eat?
        yield ms
        break
      ms.len = recEnd -! ms.mem                     #sep is NOT included
      if eat != '\0' and ms.len > 0 and ms.mem.toCstr[ms.len - 1] == eat:
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
  result = nil        #Unnecessary now?
  for i in 0 ..< n:   #Like cstrpbrk or cmemchr but for mem
    if (cast[cstring](s))[i] in accept: return s +! i

proc mem(s: string): pointer = cast[pointer](cstring(s))

template defSplit[T](slc: T, fs: var seq[MSlice], n: int, repeat: bool,
                     s: untyped, nextSep: untyped, isSep: untyped) {.dirty.} =
  fs.setLen(if n < 1: 16 else: n)
  var b   = slc.mem
  var eob = b +! slc.len
  var e: pointer
  e = nextSep(b, s, eob -! b)
  while e != nil:
    if n < 1:                               #Unbounded msplit
      if result == fs.len - 1:              #Expand capacity
        fs.setLen(if fs.len < 512: 2*fs.len else: fs.len + 512)
    elif result == n - 1:                   #Need 1 more slot for final field
      break
    fs[result].mem = b
    fs[result].len = e -! b
    result += 1
    while repeat and eob -! e > 0 and isSep((cast[cstring](e))[1], s):
      e = e +! 1
    b = e +! 1
    e = nextSep(b, s, eob -! b)
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
  ## Like ``msplit(string, var seq[MSlice], int, char)``, but return the ``seq``.
  discard msplit(s, result, sep, n, repeat)

proc msplit*(s: string, fs: var seq[MSlice], seps=wspace, n=0, repeat=true):int=
  ## Fast msplit with cached fs[] and single-char-of-set delimiter. n >= 2.
  defSplit(s, fs, n, repeat, seps, mempbrk, charIn)

proc msplit*(s: string, seps=wspace, n=0, repeat=true): seq[MSlice] {.inline.}=
  discard msplit(s, result, seps, n, repeat)

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
