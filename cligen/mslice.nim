## This module defines MSlice - basically a non-garbage-collected ``string`` -
## and various utility iterators & procs for it such as ``mSlices``&``msplit``.
## There are basically 3 kinds of splitting - file-line-like, and then delimited
## by one byte, by a set of bytes (both either repeatable|not).  The latter two
## styles can also be bounded by a number of splits/number of outputs and accept
## either ``MSlice`` or ``string`` as inputs to produce the ``seq[MSlice]``.

when not declared(File): import std/[syncio, assertions]
include cligen/unsafeAddr
from std/typetraits import supportsCopyMem
type csize = uint
proc cmemchr*(s: pointer, c: char, n: csize): pointer {.
  importc: "memchr", header: "<string.h>" .}
proc cmemrchr*(s: pointer, c: char, n: csize): pointer {.
  importc: "memchr", header: "<string.h>" .}
proc cmemcmp*(a, b: pointer, n: csize): cint {. #Exported by system/ansi_c??
  importc: "memcmp", header: "<string.h>", noSideEffect.}
proc cmemcpy*(a, b: pointer, n: csize): cint {.
  importc: "memcpy", header: "<string.h>", noSideEffect.}
proc cmemmem*(h: pointer, nH: csize, s: pointer, nS: csize): pointer {.
  importc: "memmem", header: "string.h".}
proc `-!`*(p, q: pointer): int {.inline.} =
  (cast[uint](p) - cast[uint](q)).int
proc `+!`*(p: pointer, i: int): pointer {.inline.} =
  cast[pointer](cast[uint](p) + i.uint)
proc `+!`*(p: pointer, i: uint64): pointer {.inline.} =
  cast[pointer](cast[uint64](p) + i)

type
  MSlice* = object
    ## Represent a memory slice, such as a delimited record in an `MFile`.
    ## Care is required to access `MSlice` data (think C mem\* not str\*).
    ## Use `toString` to a (reusable?) buffer for safer/compatible work.
    mem*: pointer
    len*: int

  SomeString* = string | openArray[char] | MSlice

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

template `^^`(s, i: untyped): untyped =
  (when i is BackwardsIndex: s.len - int(i) else: int(i))

template BadIndex: untyped {.used.} =
  when declared(IndexDefect): IndexDefect else: IndexError

proc `[]`*(ms: MSlice, i: int): char {.inline.} =
  when not defined(danger):
    if i >= ms.len:
      raise newException(BadIndex(), formatErrorIndexBound(i, ms.len))
  ms.mem.toCstr[i]

proc `[]=`*(ms: MSlice, i: int, c: char) {.inline.} =
  when not defined(danger):
    if i >= ms.len:
      raise newException(BadIndex(), formatErrorIndexBound(i, ms.len))
  cast[ptr char](ms.mem +! i)[] = c

proc `[]`*[T, U: Ordinal](s: MSlice, x: HSlice[T, U]): MSlice {.inline.} =
  ## Return an HSlice of an MSlice
  let o = s ^^ x.a
  result.mem = s.mem +! o
  result.len = (s ^^ x.b) - o + 1

proc mem*(s: openArray[char]): pointer =
  ## Make it easy to write a `SomeString` proc
  if s.len > 0: cast[pointer](s[0].unsafeAddr) else: nil

proc startsWith*(s: MSlice, pfx: SomeString): bool =
  ## Like `strutils.startsWith`.
  pfx.len>0 and s.len>pfx.len and cmemcmp(s.mem, pfx.mem, pfx.len.csize_t) == 0

proc endsWith*(s: MSlice, sfx: SomeString): bool =
  ## Like `strutils.endsWith`.
  sfx.len>0 and s.len>sfx.len and
    cmemcmp(s.mem +! (s.len - sfx.len), sfx.mem, sfx.len.csize_t) == 0

proc find*(s: MSlice, sub: SomeString): int =
  ## Like `strutils.find`.
  let p = cmemmem(s.mem, s.len.csize_t, sub.mem, sub.len.csize_t)
  if p.isNil: -1 else: p -! s.mem

proc toString*(ms: MSlice, s: var string) {.inline.} =
  ## Replace a Nim string ``s`` with data from an MSlice.
  s.setLen(ms.len)
  if ms.len > 0:
    copyMem(addr(s[0]), ms.mem, ms.len)

template toOpenArrayChar*(ms: MSlice): untyped =
  toOpenArray(cast[ptr UncheckedArray[char]](ms.mem), 0, ms.len - 1)

template toOpenArrayChar*(s: string): untyped =
  ## This is so you can call `toOpenArrayChar` on a `SomeString` parameter.
  toOpenArray(cast[ptr UncheckedArray[char]](s[0].addr), 0, s.len - 1)

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

proc toOb*[T](m: MSlice, ob: var T) =
  ## Assumes `m` starts at beginning of object `ob`! Reads data in slice
  ## into object `ob` using `copyMem`.
  doAssert m.len >= ob.sizeof
  when supportsCopyMem(T):
    copyMem ob.addr, m.mem, ob.sizeof
  else:
    {.error: "`ob` type does not support copyMem".}

proc toSeq*[T](m: MSlice, s: var seq[T]) =
  ## Reads data in slice `s` into object `seq[T]` using `copyMem`.
  ##
  ## Assumes `m` starts at beginning of seq `s`! `T` must either be a flat
  ## object type or tuple of flat objects (no indirections allowed).
  let size = m.len div sizeof(T)
  s = newSeq[T](size)
  doAssert m.len >= size
  when supportsCopyMem(T):
    copyMem s[0].addr, m.mem, m.len
  else:
    {.error: "`ob` type does not support copyMem".}

proc `==`*(a: string, ms: MSlice): bool {.inline.} =
  a.len == ms.len and cmemcmp(unsafeAddr a[0], ms.mem, a.len.csize) == 0
proc `==`*(ms: MSlice, b: string): bool {.inline.} = b == ms

import std/hashes # hashData
proc hash*(ms: MSlice): Hash {.inline.} =
  ## hash MSlice data; With ``==`` all we need to put in a Table/Set
  result = hashData(ms.mem, ms.len)

proc nextSlice*(mslc, ms: var MSlice, sep='\n', eat='\0'): int =
  ## Stores everything from the start of ``mslc`` up to excluding the next
  ## ``sep`` in ``ms`` and advances the input slice ``mslc`` to after the next
  ## separator. Optionally removes ``eat``-suffixed char from the end of the
  ## resulting slice.
  ##
  ## Returns the number of advanced characters.
  ##
  ## If no further `sep` is found in the input, the remaining slice is
  ## in `ms` and `mslc` will be considered empty.
  ##
  ## If `mslc` is nil, `ms` remains unchanged.
  ##
  ## This procedure is somewhat analogous to reading from a stream, in the
  ## sense that the input slice is drained.
  if mslc.mem != nil:
    var remaining = mslc.len
    if remaining > 0:
      let recEnd = cmemchr(mslc.mem, sep, remaining.csize)
      if recEnd == nil:                         #Unterminated final slice
        ms.len = remaining                      #Weird case..consult eat?
        ms.mem = mslc.mem
        mslc.len = 0                            # empty input slice
        # set input memory to nil?
        # mslc.mem = nil
        return remaining
      ms.mem = mslc.mem                         # assign output slice
      ms.len = recEnd -! mslc.mem               # sep is NOT included
      if eat != '\0' and ms.len > 0 and ms[ms.len - 1] == eat:
        dec(ms.len)                             # trim pre-sep char
      mslc.mem = recEnd +! 1                    # advance input & skip sep
      result = mslc.mem -! ms.mem               # calc number of advanced idxs
      mslc.len = mslc.len - result              # and adjust input length

iterator mSlices*(mslc: MSlice, sep=' ', eat='\0'): MSlice =
  ## Iterate over {optionally ``eat``-suffixed} ``sep``-delimited slices in
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

proc firstN*(ms: MSlice, n=1, term='\n'): MSlice =
  ## Return the first `n` `term`-terminated records, including all terminators.
  result.mem = ms.mem
  var i = 1
  for s in ms.mSlices(term):
    if i >= n:
      result.len = s.mem +! s.len +! 1 -! ms.mem
      break
    inc i

const wspace* = {' ', '\t', '\v', '\r', '\n', '\f'}  ## == strutils.Whitespace

proc charEq(x, c: char): bool {.inline.} = x == c

proc charIn(x: char, c: set[char]): bool {.inline.} = x in c

proc mempbrk*(s: pointer, accept: set[char], n: csize): pointer {.inline.} =
  for i in 0 ..< int(n):  #Like cstrpbrk or cmemchr but for mem
    if (cast[cstring](s))[i] in accept: return s +! i

proc stripLeading*(s: var MSlice, chars=wspace) =
  while s.len > 0 and cast[cstring](s.mem)[0] in chars:
    s.mem = s.mem +! 1
    s.len -= 1

proc stripTrailing*(s: var MSlice, chars=wspace) =
  while s.len > 0 and cast[cstring](s.mem)[s.len - 1] in chars: s.len -= 1

proc strip*(s: var MSlice, leading=true, trailing=true, chars=wspace) =
  if leading: s.stripLeading chars
  if trailing: s.stripTrailing chars

proc stripLeading*(s: MSlice, chars=wspace): MSlice =
  result = s; result.stripLeading chars

proc stripTrailing*(s: MSlice, chars=wspace): MSlice =
  result = s; result.stripTrailing chars

proc strip*(s: MSlice, leading=true, trailing=true, chars=wspace): MSlice =
  result = s; result.strip leading, trailing, chars

template defSplit[T](slc: T, fs: var seq[MSlice], n: int, repeat: bool,
                     sep: untyped, nextSep: untyped, isSep: untyped) {.dirty.} =
  fs.setLen(if n < 1: 16 else: n)
  var b   = slc.mem
  var eob = b +! slc.len
  while repeat and eob -! b > 0 and isSep((cast[cstring](b))[0], sep):
    b = b +! 1
    if b == eob: fs.setLen(0); return
  var e = nextSep(b, sep, min(int.high.csize, (eob -! b).csize))
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
  ## Fast msplit with cached `fs[]` and single-char-of-set delimiter. n >= 2.
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
  var e = nextSep(b, sep, min(int.high.csize, (eob -! b).csize))
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
  ##split w/reused `fs[]`, bounded cols char-of-set sep which can maybe repeat.
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
  if seps.len == 0:
    raise newException(ValueError, "Empty seps disallowed")
  elif seps[0] == 'w':          #User can use other permutation if cset needed
    result.repeat = true
    result.chrDlm = ' '
    result.setDlm = wspace
    result.n      = wspace.card #=6 unless wspace defn changes
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
  ## Fill `seq` w/all `sep`-separated `TextFrame` in `s` split `<=n` times
  ## (0=unlim).
  fs.setLen 0
  for f in s.frame(sep): fs.add f
  fs.len

proc frame*(s: MSlice, sep: Sep, n=0): seq[TextFrame] =
  ## Return `seq` of all `sep`-separated `TextFrame` in `s` split `<=n` times
  ## (0=unlim).
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

proc toSeq(sset: set[uint8]): seq[uint8] =
  for s in sset: result.add s
proc makeDigits(cset: set[char], vals: seq[uint8]): array[256, char] =
  for i in 0..255: result[i] = chr(255)
  var i = 0
  for c in cset: result[ord(c)] = char(vals[i]); inc i
const digits2  = makeDigits({'0', '1'}, {0'u8, 1'u8}.toSeq)
const digits8  = makeDigits({'0'..'7'}, {0'u8..7'u8}.toSeq)
const digits10 = makeDigits({'0'..'9'}, {0'u8..9'u8}.toSeq)
const digits16 = makeDigits({'0'..'9', 'A'..'F', 'a'..'f'},
                      {0'u8..9'u8, 10'u8..15'u8}.toSeq & {10'u8..15'u8}.toSeq)
var doNotUse: int # Only for default value; Callers must provide `eoNum`.
template parseInts(s, base, digits, eoNum): untyped =
  var neg = false
  var i = 0; var x = 0'u
  if s.len > 0:
    if   s[0] == '-': neg = true; inc i
    elif s[0] == '+': inc i
  while i < s.len:
    let dig = digits[ord(s[i])].uint
    if dig >= base: break
    x *= base
    x += dig
    inc i                               # below `not` assumes 2's complement..
  eoNum = i                             #..&does not handle overflow gracefully.
  cast[int](if neg: 1'u + not x else: x)

proc parseBin*(s: MSlice|openArray[char]; eoNum: var int = doNotUse): int =
  ## Parse `s` as a binary int without first creating a string; error => 0.
  ## Passing some `eoNum` & checking `eoNum==s.len` tests this condition.
  parseInts(s, 2'u, digits2, eoNum)

proc parseOct*(s: MSlice|openArray[char]; eoNum: var int = doNotUse): int =
  ## Parse `s` as an octal int without first creating a string; error => 0.
  ## Passing some `eoNum` & checking `eoNum==s.len` tests this condition.
  parseInts(s, 8'u, digits8, eoNum)

proc parseInt*(s: MSlice|openArray[char]; eoNum: var int = doNotUse): int =
  ## Parse `s` as a decimal int without first creating a string; error => 0.
  ## Passing some `eoNum` & checking `eoNum==s.len` tests this condition.
  parseInts(s, 10'u, digits10, eoNum)

proc parseHex*(s: MSlice|openArray[char]; eoNum: var int = doNotUse): int =
  ## Parse `s` as a hexadecimal int without first creating a string; error => 0.
  ## Passing some `eoNum` & checking `eoNum==s.len` tests this condition.
  parseInts(s, 16'u, digits16, eoNum)

# May seem big, BUT <15% of L1 & real life cache line usage light (sim OOMags).
const pow10*: array[-308..308, float] = [
 1e-308, 1e-307, 1e-306, 1e-305, 1e-304, 1e-303, 1e-302, 1e-301, 1e-300, 1e-299,
 1e-298, 1e-297, 1e-296, 1e-295, 1e-294, 1e-293, 1e-292, 1e-291, 1e-290, 1e-289,
 1e-288, 1e-287, 1e-286, 1e-285, 1e-284, 1e-283, 1e-282, 1e-281, 1e-280, 1e-279,
 1e-278, 1e-277, 1e-276, 1e-275, 1e-274, 1e-273, 1e-272, 1e-271, 1e-270, 1e-269,
 1e-268, 1e-267, 1e-266, 1e-265, 1e-264, 1e-263, 1e-262, 1e-261, 1e-260, 1e-259,
 1e-258, 1e-257, 1e-256, 1e-255, 1e-254, 1e-253, 1e-252, 1e-251, 1e-250, 1e-249,
 1e-248, 1e-247, 1e-246, 1e-245, 1e-244, 1e-243, 1e-242, 1e-241, 1e-240, 1e-239,
 1e-238, 1e-237, 1e-236, 1e-235, 1e-234, 1e-233, 1e-232, 1e-231, 1e-230, 1e-229,
 1e-228, 1e-227, 1e-226, 1e-225, 1e-224, 1e-223, 1e-222, 1e-221, 1e-220, 1e-219,
 1e-218, 1e-217, 1e-216, 1e-215, 1e-214, 1e-213, 1e-212, 1e-211, 1e-210, 1e-209,
 1e-208, 1e-207, 1e-206, 1e-205, 1e-204, 1e-203, 1e-202, 1e-201, 1e-200, 1e-199,
 1e-198, 1e-197, 1e-196, 1e-195, 1e-194, 1e-193, 1e-192, 1e-191, 1e-190, 1e-189,
 1e-188, 1e-187, 1e-186, 1e-185, 1e-184, 1e-183, 1e-182, 1e-181, 1e-180, 1e-179,
 1e-178, 1e-177, 1e-176, 1e-175, 1e-174, 1e-173, 1e-172, 1e-171, 1e-170, 1e-169,
 1e-168, 1e-167, 1e-166, 1e-165, 1e-164, 1e-163, 1e-162, 1e-161, 1e-160, 1e-159,
 1e-158, 1e-157, 1e-156, 1e-155, 1e-154, 1e-153, 1e-152, 1e-151, 1e-150, 1e-149,
 1e-148, 1e-147, 1e-146, 1e-145, 1e-144, 1e-143, 1e-142, 1e-141, 1e-140, 1e-139,
 1e-138, 1e-137, 1e-136, 1e-135, 1e-134, 1e-133, 1e-132, 1e-131, 1e-130, 1e-129,
 1e-128, 1e-127, 1e-126, 1e-125, 1e-124, 1e-123, 1e-122, 1e-121, 1e-120, 1e-119,
 1e-118, 1e-117, 1e-116, 1e-115, 1e-114, 1e-113, 1e-112, 1e-111, 1e-110, 1e-109,
 1e-108, 1e-107, 1e-106, 1e-105, 1e-104, 1e-103, 1e-102, 1e-101, 1e-100, 1e-99,
 1e-98, 1e-97, 1e-96, 1e-95, 1e-94, 1e-93, 1e-92, 1e-91, 1e-90, 1e-89, 1e-88,
 1e-87, 1e-86, 1e-85, 1e-84, 1e-83, 1e-82, 1e-81, 1e-80, 1e-79, 1e-78, 1e-77,
 1e-76, 1e-75, 1e-74, 1e-73, 1e-72, 1e-71, 1e-70, 1e-69, 1e-68, 1e-67, 1e-66,
 1e-65, 1e-64, 1e-63, 1e-62, 1e-61, 1e-60, 1e-59, 1e-58, 1e-57, 1e-56, 1e-55,
 1e-54, 1e-53, 1e-52, 1e-51, 1e-50, 1e-49, 1e-48, 1e-47, 1e-46, 1e-45, 1e-44,
 1e-43, 1e-42, 1e-41, 1e-40, 1e-39, 1e-38, 1e-37, 1e-36, 1e-35, 1e-34, 1e-33,
 1e-32, 1e-31, 1e-30, 1e-29, 1e-28, 1e-27, 1e-26, 1e-25, 1e-24, 1e-23, 1e-22,
 1e-21, 1e-20, 1e-19, 1e-18, 1e-17, 1e-16, 1e-15, 1e-14, 1e-13, 1e-12, 1e-11,
 1e-10, 1e-9, 1e-8, 1e-7, 1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1.0, 1e1, 1e2,1e3,
 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17,
 1e18, 1e19, 1e20, 1e21, 1e22, 1e23, 1e24, 1e25, 1e26, 1e27, 1e28, 1e29, 1e30,
 1e31, 1e32, 1e33, 1e34, 1e35, 1e36, 1e37, 1e38, 1e39, 1e40, 1e41, 1e42, 1e43,
 1e44, 1e45, 1e46, 1e47, 1e48, 1e49, 1e50, 1e51, 1e52, 1e53, 1e54, 1e55, 1e56,
 1e57, 1e58, 1e59, 1e60, 1e61, 1e62, 1e63, 1e64, 1e65, 1e66, 1e67, 1e68, 1e69,
 1e70, 1e71, 1e72, 1e73, 1e74, 1e75, 1e76, 1e77, 1e78, 1e79, 1e80, 1e81, 1e82,
 1e83, 1e84, 1e85, 1e86, 1e87, 1e88, 1e89, 1e90, 1e91, 1e92, 1e93, 1e94, 1e95,
 1e96, 1e97, 1e98, 1e99, 1e100, 1e101, 1e102, 1e103, 1e104, 1e105, 1e106, 1e107,
 1e108, 1e109, 1e110, 1e111, 1e112, 1e113, 1e114, 1e115, 1e116, 1e117, 1e118,
 1e119, 1e120, 1e121, 1e122, 1e123, 1e124, 1e125, 1e126, 1e127, 1e128, 1e129,
 1e130, 1e131, 1e132, 1e133, 1e134, 1e135, 1e136, 1e137, 1e138, 1e139, 1e140,
 1e141, 1e142, 1e143, 1e144, 1e145, 1e146, 1e147, 1e148, 1e149, 1e150, 1e151,
 1e152, 1e153, 1e154, 1e155, 1e156, 1e157, 1e158, 1e159, 1e160, 1e161, 1e162,
 1e163, 1e164, 1e165, 1e166, 1e167, 1e168, 1e169, 1e170, 1e171, 1e172, 1e173,
 1e174, 1e175, 1e176, 1e177, 1e178, 1e179, 1e180, 1e181, 1e182, 1e183, 1e184,
 1e185, 1e186, 1e187, 1e188, 1e189, 1e190, 1e191, 1e192, 1e193, 1e194, 1e195,
 1e196, 1e197, 1e198, 1e199, 1e200, 1e201, 1e202, 1e203, 1e204, 1e205, 1e206,
 1e207, 1e208, 1e209, 1e210, 1e211, 1e212, 1e213, 1e214, 1e215, 1e216, 1e217,
 1e218, 1e219, 1e220, 1e221, 1e222, 1e223, 1e224, 1e225, 1e226, 1e227, 1e228,
 1e229, 1e230, 1e231, 1e232, 1e233, 1e234, 1e235, 1e236, 1e237, 1e238, 1e239,
 1e240, 1e241, 1e242, 1e243, 1e244, 1e245, 1e246, 1e247, 1e248, 1e249, 1e250,
 1e251, 1e252, 1e253, 1e254, 1e255, 1e256, 1e257, 1e258, 1e259, 1e260, 1e261,
 1e262, 1e263, 1e264, 1e265, 1e266, 1e267, 1e268, 1e269, 1e270, 1e271, 1e272,
 1e273, 1e274, 1e275, 1e276, 1e277, 1e278, 1e279, 1e280, 1e281, 1e282, 1e283,
 1e284, 1e285, 1e286, 1e287, 1e288, 1e289, 1e290, 1e291, 1e292, 1e293, 1e294,
 1e295, 1e296, 1e297, 1e298, 1e299, 1e300, 1e301, 1e302, 1e303, 1e304, 1e305,
 1e306, 1e307, 1e308] ## `pow10[i] = 10^i` as a float

proc parseFloat*(s: MSlice|openArray[char]; eoNum: var int = doNotUse): float =
  proc copysign(x, y: cdouble): cdouble {.importc, header: "<math.h>".}
  template doReturn(j, x) = eoNum = j; return x
  var decimal = 0'u64
  var j = 0
  if s.len < 1 or s.mem.isNil: doReturn(0, 0.0)
  var sgn = 1.0; var esgn = 1
  var exp, po10, nDig: int
  var ixPt = -1                               # index(decPoint)
  case s[j]                                   # Process 1st byte
  of '-': sgn = -1.0; inc j
  of '+': inc j                               # 1st do w/+-inf,NAN,just,[-+nNiI]
  of 'N': (if s.len > 2 and s[1]=='A' and s[2]=='N': doReturn(s.len, NaN))
  of 'n': (if s.len > 2 and s[1]=='a' and s[2]=='n': doReturn(s.len, NaN))
  of 'I': (if s.len > 2 and s[1]=='N' and s[2]=='F': doReturn(s.len, Inf))
  of 'i': (if s.len > 2 and s[1]=='n' and s[2]=='f': doReturn(s.len, Inf))
  else: discard
  case s[j]
  of 'I': (if s.len > 2 and s[1]=='N' and s[2]=='F': doReturn(s.len, sgn*Inf))
  of 'i': (if s.len > 2 and s[1]=='n' and s[2]=='f': doReturn(s.len, sgn*Inf))
  else: discard
  while j < s.len:                            #Find '.'; process dig build scale
    if s[j] < '0' or s[j] > '9':              #   a non-decimal digit
      if s[j] != '.' or ixPt >= 0: break      #   check for [Ee] directly?
      ixPt = nDig; dec nDig                   #   reverse loop's inc nDig
    elif nDig < 19:                           #   Room4more digits in decimal
      let dig = digits10[ord(s[j])].uint64    #   (2**64=1.84e19=>19 digits ok)
      decimal = 10'u64 * decimal + dig        #   CORE ASCII->BINARY TRANSFORM
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
  eoNum = j
  copysign(decimal.float * pow10[exp], sgn)   # Assemble result

when isMainModule:  #Run tests with n<1, nCol, <nCol, repeat=false,true.
  when not declared(addFloat): import std/formatfloat
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

  template tflt(s, expect) =
    let o  = $s.toMSlice.parseFloat
    if o != expect: echo "FAIL: ", s, "\t\t", o
  let testPairs = [
    ("0042"     , "42.0"  ), ("42"        , "42.0"  ), ("42e-01"    , "4.2"   ),
    ("42e+01"   , "420.0" ), ("42e-1"     , "4.2"   ), ("42e1"      , "420.0" ),
    ("682.2"    , "682.2" ), ("682.2e1"   , "6822.0"), ("682.2e01"  , "6822.0"),
    ("682.2e+01", "6822.0"), ("682.2e-01" , "68.22" ), ("682.2e-1"  , "68.22" ),
  # ("0042.5"   , "42.5"  ), ("0042.5e-01", "4.2"   ), ("0042.5e+01", "425.0" ),
  # ("0042.5e-1", "4.25"  ), ("0042.5e1"  , "425.0" ), ("0042e-01"  , "4.2"   ),
  # ("0042e+01" , "420.0" ), ("0042e-1"   , "4.2"   ), ("0042e1"    , "420.0" ),
  ]
  for pair in testPairs: tflt       pair[0],       pair[1]
  for pair in testPairs: tflt "+" & pair[0],       pair[1]
  for pair in testPairs: tflt "-" & pair[0], "-" & pair[1]
