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

proc `[]=`*(ms: MSlice, i: int, c: char) {.inline.} =
  cast[ptr char](ms.mem +! i)[] = c

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

type Sep* = tuple[repeat: bool, chrDlm: char, setDlm: set[char], n: int]

proc initSep*(seps: string): Sep =
  ## Abstract single-string hybrid spec of maybe repeat-folding 1-char | maybe
  ## repeat-folding char set separation.  Specifically, if any char of `seps`
  ## repeats, separators fold while value diversity implies char set separation.
  ## A magic val `"white"` = folding white space chars.  E.g.: `","` = strict
  ## CSV, `"<SPC><SPC>"` = folding spaces `" "` = strict spaces.
  if seps == "white":           #User can use other permutation if cset needed
    result.repeat = true
    result.chrDlm = ' '
    result.setDlm = wspace
    result.n      = wspace.card #=6 unless wspace defn changes
  elif seps.len == 0:
    raise newException(ValueError, "Empty seps disallowed")
  else:
    for d in seps: result.setDlm.incl d
    result.n = result.setDlm.card
    result.chrDlm = seps[0]
    result.repeat = result.setDlm.card < seps.len

type Splitr* {.deprecated: "use Sep".} = Sep
proc initSplitr*(seps: string): Sep {.deprecated: "use initSep".}= initSep(seps)

proc split*(s: Sep, line: MSlice, cols: var seq[MSlice], n=0) {.inline.} =
  if s.n > 1: discard msplit(line, cols, seps=s.setDlm, n, s.repeat)
  else      : discard msplit(line, cols, s.chrDlm     , n, s.repeat)

proc split*(s: Sep, line: string, cols: var seq[string], n=0) {.inline.} =
  if s.n > 1: discard splitr(line, cols, seps=s.setDlm, n, s.repeat)
  else      : discard splitr(line, cols, s.chrDlm     , n, s.repeat)

proc split*(s: Sep, line: string, n=0): seq[string] {.inline.} =
  s.split(line, result, n)

# `frame` APIs include separations unlike `split` APIs. Specifically, iterators
# yield `2*j+1` times where `j`=count of separations|splits.  If input starts
# with a separator, the initial yield is an empty data frame `.ms.len==0` while
# if input ends with one the final yield is also an empty data frame.  Callers
# can check `len` to decide what to do for such cases and may want special EOS
# logic.  For repeating separator variants, `.isSep` strictly toggles between
# `true|false`.  { So, only initial or final data slices can be empty. }

type TextFrame* = tuple[ms: MSlice, isSep: bool] ## sep|data, flag => which

template defFrame(s: MSlice; n: int; repeat: bool; sep, next, eq: untyped) =
  if s.mem != nil:
    var f: TextFrame = (MSlice(mem: s.mem, len: 0), false)
    var left = s.len
    var j = 0
    while left > 0 and (let d = next(f.ms.mem, sep, left.uint); d) != nil:
      j.inc
      if n != 0 and j > n: break
      f.ms.len = d -! f.ms.mem
      f.isSep  = false
      yield f                           # yield data
      left.dec f.ms.len + 1
      f.ms.mem = d
      f.ms.len = 1
      if repeat:
        while left > 0 and eq(sep, cast[ptr char](f.ms.mem +! f.ms.len)[]):
          f.ms.len.inc; left.dec
      f.isSep  = true
      yield f                           # yield separator
      f.ms.mem = d +! f.ms.len          # set up for next loop
    f.isSep = false                     # last frame always data
    f.ms.len = left                     # but empty if left == 0
    yield f

iterator frame1(s: MSlice, sep: char, n=0): TextFrame =
  defFrame(s, n, false, sep, cmemchr, `==`)

iterator frame1(s: MSlice, seps: set[char], n=0): TextFrame =
  defFrame(s, n, false, seps, mempbrk, contains)

iterator frameR(s: MSlice, sep: char, n=0): TextFrame =
  defFrame(s, n, true, sep, cmemchr, `==`)

iterator frameR(s: MSlice, seps: set[char], n=0): TextFrame =
  defFrame(s, n, true, seps, mempbrk, contains)

iterator frame*(s: MSlice, sep: char, repeat=false, n=0): TextFrame =
  ## Iterate over `TextFrame`s (data|sep slices) in `s` delimited by a single
  ## char `sep` split `<=n` times.  Repeats are folded `if repeat`.
  if repeat:
    for f in s.frameR(sep, n): yield f
  else:
    for f in s.frame1(sep, n): yield f

iterator frame*(s: MSlice, seps: set[char], repeat=false, n=0): TextFrame =
  ## Iterate over `TextFrame`s (data|sep slices) in `s` delimited by a
  ## `set[char] seps` split `<=n` times.  Repeats are folded `if repeat`.
  if repeat:
    for f in s.frameR(seps, n): yield f
  else:
    for f in s.frame1(seps, n): yield f

iterator frame*(s: MSlice, sep: Sep, n=0): TextFrame =
  ## Yield all `sep`-separated `TextFrame` in `s` split `<=n` times (0=unlim).
  ##
  ## .. code-block:: nim
  ##   let x = "hi there you "
  ##   for tok in x.toMSlice.frame(" ".initSep, n=1): echo $tok
  if sep.n == 1:
    for f in s.frame(sep.chrDlm, sep.repeat, n): yield f
  else:
    for f in s.frame(sep.setDlm, sep.repeat, n): yield f

proc frame*(s: MSlice, fs: var seq[TextFrame], sep: Sep, n=0): int =
  ## Fill `seq` w/all `sep`-separated `TextFrame` in `s` split `<=n` times (0=unlim).
  fs.setLen 0
  for f in s.frame(sep): fs.add f
  fs.len

proc frame*(s: MSlice, sep: Sep, n=0): seq[TextFrame] =
  ## Return `seq` of all `sep`-separated `TextFrame` in `s` split `<=n` times (0=unlim).
  ##
  ## .. code-block:: nim
  ##   let x = "hi there you "
  ##   for tok in x.toMSlice.frame(" ".initSep, n=1): echo $tok
  discard s.frame(result, sep, n)

iterator items*(a: MSlice): char {.inline.} =
  ## Iterates over each char of `a`.
  for i in 0 ..< a.len:
    yield a[i]

iterator pairs*(a: MSlice): tuple[ix: int; c: char] {.inline.} =
  ## Yields each (index,char) in `a`.
  for i in 0 ..< a.len:
    yield (i, a[i])

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

template toOpenArrayChar*(ms: MSlice): untyped =
  toOpenArray(cast[ptr UncheckedArray[char]](ms.mem), 0, ms.len - 1)

proc eos*(ms: MSlice): pointer {.inline.} = ms.mem +! ms.len
  ## Address 1 past last valid byte in slice

proc extend*(ms: MSlice, max: int, sep = '\n'): MSlice {.inline.} =
  ## If `ms` does not end in `sep` then extend until it does or `ms.len==max`
  ## whichever comes first.
  if ms.len > 0 and cast[ptr char](ms.mem +! (ms.len - 1))[] == sep:
    return ms
  result.mem = ms.mem
  let eos = ms.eos
  let next = cmemchr(eos, sep, (max - ms.len).csize)
  result.len = if next != nil: (next -! eos + ms.len + 1) else: max

proc nSplit*(n: int, data: MSlice, sep = '\n'): seq[MSlice] =
  ## Split `data` into `n` roughly equal parts delimited by `sep` with any
  ## separator included in slices.  `result.len` can be < `n` for small `data`
  ## sizes (in number of `sep`s, not bytes).  For IO efficiency, subdivision
  ## is done by bytes as a guess.  So, this is fast, but accuracy is limited by
  ## statistical regularity.
  if n < 2: result.add data             # n<1 & n<0 swept into just n==1 no-op
  else:
    let eod  = data.eos
    let step = max(data.len div n, 1)
    result.add extend(MSlice(mem: data.mem, len: step), data.len, sep)
    var eos = result[^1].eos
    while cast[uint](eos) < cast[uint](eod) and result.len < n:
      let mx = eod -! eos               # maximum slice length
      result.add extend(MSlice(mem: eos, len: min(mx, step)), mx, sep)
      eos = result[^1].eos              # update End Of Slice
    result[^1].len = data.len - (result[^1].mem -! data.mem)

import strutils

proc makeDigits(): array[256, char] =
  for i in 0..255: result[i] = chr(255)
  for i in {'0'..'9'}: result[ord(i)] = chr(ord(i) - ord('0'))
const digits10 = makeDigits()

proc parseInt*(s: MSlice; eoNum: ptr int=nil): int =
  ## parse `MSlice` as an integer without first creating a string; error => 0.
  ## Passing some `eoNum.addr` & checking `eoNum==s.len` tests this condition.
  var neg = false
  var i = 0; var x = 0
  if s.len > 0:
    if   s[0] == '-': neg = true; inc i
    elif s[0] == '+': inc i
  while i < s.len:
    let dig = digits10[ord(s[i])].int
    if dig >= 10: break
    x *= 10
    x += dig
    inc i
  if not eoNum.isNil: eoNum[] = i
  result = if i == s.len: x else: 0

proc pow10(e: int64): float {.inline.} =
  const p10 = [1e-22, 1e-21, 1e-20, 1e-19, 1e-18, 1e-17, 1e-16, 1e-15, 1e-14,
               1e-13, 1e-12, 1e-11, 1e-10, 1e-09, 1e-08, 1e-07, 1e-06, 1e-05,
               1e-4, 1e-3, 1e-2, 1e-1, 1.0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7,
               1e8, 1e9]                        # 4*64B cache lines = 32 slots
  if -22 <= e and e <= 9:
    return p10[e + 22]                          # common case=small table lookup
  result = 1.0
  var base = 10.0
  var e = e
  if e < 0:
    e = -e
    base = 0.1
  while e != 0:
    if (e and 1) != 0:
      result *= base
    e = e shr 1
    base *= base

proc parseFloat*(s: MSlice; eoNum: ptr int=nil): float =
  template doReturn(j,x) = (if not eoNum.isNil: eoNum[] = j; return x)
  var decimal = 0'u64
  var j = 0
  if s.len < 1 or s.mem.isNil: doReturn(0, 0.0)
  var sgn = 1.0; var esgn = 1
  var exp, po10: int
  var nDig {.noInit}, ixPt {.noInit}: int     # index(decPoint)
  case s[j]                                   # Process 1st byte
  of '-': sgn = -1.0; inc j
  of '+': inc j
  of 'N': (if s.len > 2 and s[1]=='A' and s[2]=='N': doReturn(s.len, NAN))
  of 'n': (if s.len > 2 and s[1]=='a' and s[2]=='n': doReturn(s.len, NAN))
  of 'I': (if s.len > 2 and s[1]=='N' and s[2]=='F': doReturn(s.len, INF))
  of 'i': (if s.len > 2 and s[1]=='n' and s[2]=='f': doReturn(s.len, INF))
  else: discard
  case s[j]
  of 'I': (if s.len > 2 and s[1]=='N' and s[2]=='F': doReturn(s.len, sgn*INF))
  of 'i': (if s.len > 2 and s[1]=='n' and s[2]=='f': doReturn(s.len, sgn*INF))
  else: discard
  ixPt = -1                                   # Done w/+-inf,NAN,just,[-+nNiI]
  nDig = 0                                    # Find radix; process digits
  while j < s.len:                            #   build scale factor
    if s[j] < '0' or s[j] > '9':              #   a non-decimal digit
      if s[j] != '.' or ixPt >= 0: break      #   check for [Ee] directly?
      dec nDig; ixPt = nDig                   #   reverse loop's inc nDig
    elif nDig < 19:                           #   Room4more digits in decimal
      let dig = digits10[ord(s[j])].uint64    #   (2**64=1.84e19=>19 digits ok)
      decimal = 10*decimal + dig              #   CORE ASCII->BINARY TRANSFORM
    else:
      inc po10
    inc j
    inc nDig
  if ixPt < 0: ixPt = nDig                    # no radix; set to eoNum
  elif nDig == 1: doReturn(0, 0.0)            # was *only* a radix.
  if j < s.len and (s[j] == 'E' or s[j] == 'e'):
    inc j
    if   s[j] == '+': inc j
    elif s[j] == '-': inc j; esgn = -1
    while j < s.len and s[j] >= '0' and s[j] <= '9':
      exp = 10*exp + ord(s[j]) - ord('0')     # decimal exponent
      inc j
  exp = (ixPt - nDig + po10) + esgn * exp     # Combine implicit&explicit exp
  if not eoNum.isNil: eoNum[] = s.len
  result = sgn * decimal.float * pow10(exp)   # Assemble result

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
