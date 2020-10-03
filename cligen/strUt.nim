import std/[strutils, sets]

proc hashCB*(x: openArray[char]): uint64 =
  ## Hash inspired by Fletcher1982-Arithmetic Checksum. Please credit him&me!
  ## I adapted to use salt, 8B digits (filled native-Endian) & accumulators
  ## truncated via unsigned long overflow, and R=3 (in paper's terminology).
  ## This passes few SMHasher tests, but is ok in practice, fast & portable.
  var h1 = 0xd225f207b86b6161'u64   #Just a big initial number to start things
  var h2 = 0xf554651de2ae3773'u64   #NOTE This needs some Big-Endian analogue
  var h3 = h1 * h2                  #  .. for hash values to be more portable.
  let n = x.len
  if n == 0:
    return h1
  for i in countup(0, n - 1, 8):    #Word-wise loop helps speed
    h1 += cast[ptr uint64](unsafeAddr x[i])[]
    h2 += h1
    h3 += h2
  if (n and 7) != 0:                #Copy any final partial word to temp int
    var partialWord: uint64 = 0
    copyMem(addr partialWord, unsafeAddr x[n shr 3 shl 3], n and 7)
    h1 += partialWord         #NOTE Simple final sum works ok as a file chksum,
    h2 += h1                  #     but for Table apps using only SOME bits on
    h3 += h2                  #     maybe short strs, better to optim tail cpy
  return h1 + h2 + h3         #     & finalize w/something like rotr(h2*h3,38).

proc r8(p: pointer): uint64 {.inline.} = copyMem(addr result, p, 8)

when defined(gcc) or defined(llvm_gcc) or defined(clang):
  #Machinery for accessing xpro=(hi^lo)(128 bit product) on gcc/clang backends.
  {.emit: "typedef unsigned __int128 NU128;".}
  type uint128 {.importc: "NU128".} = tuple[h, l: uint64]
  func tm(x,y:uint64):uint128={.emit:"`result`=((NU128)(`x`))*((NU128)(`y`));".}
  func lo(x:uint128): uint64 = {.emit:"`result` = (NU64)(NU128)(`x`);".}
  func hi(x:uint128): uint64 = {.emit:"`result` = (NU64)((NU128)(`x`) >> 64);".}
  func xpro(A: uint64, B: uint64): uint64 = #Xor of high & low 8B of product
    var product = tm(A, B)
    return hi(product) xor lo(product)

  proc wyBlock(x: pointer): uint64 {.inline.} =
    proc `+`(p:pointer,i:int):pointer {.inline.}=cast[pointer](cast[int](p)+%i)
    const P1 = 0xe7037ed1a0b428db'u64; const P2 = 0x8ebc6af09c88c6e3'u64
    const P3 = 0x589965cc75374cc3'u64; const P4 = 0x1d8e4e27c47d124f'u64
    xpro(r8(x) xor P1, r8(x+8) xor P2) xor xpro(r8(x+16) xor P3,r8(x+24) xor P4)
else:
  func xpro(A: uint64, B: uint64): uint64 = #Xor of high & low 8B of product
    A xor B

  proc wyBlock(x: pointer): uint64 {.inline.} =
    proc `+`(p:pointer,i:int):pointer {.inline.}=cast[pointer](cast[int](p)+%i)
    const P1 = 0xe7037ed1a0b428db'u64; const P2 = 0x8ebc6af09c88c6e3'u64
    const P3 = 0x589965cc75374cc3'u64; const P4 = 0x1d8e4e27c47d124f'u64
    xpro(r8(x) xor P1, r8(x+8) xor P2) xor xpro(r8(x+16) xor P3,r8(x+24) xor P4)

proc hashWY*(x: openArray[char]): uint64 =
  ## Wang Yi's nice hash passing SMHasher tests; *Unoptimized* for small keys
  const P0 = 0xa0761d6478bd642f'u64; const P5 = 0xeb44accab455d165'u64
  var h = 0'u64                     #Could seed/carry forward a hash here
  let n = x.len
  for i in countup(0, n - 32, 32):  #Block-wise loop helps speed
    h = xpro(h xor P0, wyBlock(unsafeAddr x[i]))
  if (n and 31) != 0:               #Copy any final partial block to temp buf
    var q: array[32, char]
    copyMem(unsafeAddr q[0], unsafeAddr x[n shr 5 shl 5], n and 31)
    h = xpro(h xor P0, wyBlock(unsafeAddr q[0])) #WY SmallKey opt=>diff hshVal
  return xpro(h, uint64(n) xor P5)
#NOTE 27+n/6 cycles has a BIG constant; Could explode into 31 cases like WY(or
#use ANY staged hashes for final 2,4,8,16,31B since len%32 is deterministic).

proc startsWithI*(s, prefix: string): bool {.noSideEffect.} =
  ##Case insensitive variant of startsWith.
  var i = 0
  while true:
    if i >= prefix.len: return true
    if i >= s.len or s[i].toLowerAscii != prefix[i].toLowerAscii: return false
    inc(i)

proc endsWithI*(s, suffix: string): bool {.noSideEffect.} =
  ##Case insensitive variant of endsWith.
  var i = 0
  var j = len(s) - len(suffix)
  while i+j >= 0 and i+j < s.len:
    if s[i+j].toLowerAscii != suffix[i].toLowerAscii: return false
    inc(i)
  if i >= suffix.len: return true

proc `-`*(a, b: seq[string]): seq[string] =
  ## All a[]s not in b (implemented efficiently with a HashSet).
  when (NimMajor,NimMinor,NimPatch) < (0,20,0):
    var sb = initSet[string](rightSize(b.len))
    for s in b: sb.incl s
  else:
    var sb = toHashSet(b)
  for s in a:
    if s notin sb: result.add s

proc split*[T](st: seq[T], delim: T): seq[seq[T]] =
  ## Return seq of sub-seqs split by ``delim``.  Delim itself is not included.
  ## E.g. ``@["a", "--", "b", "c"].split "--" == @[@["a"], @["b", "c"]]``.
  var sub: seq[string]
  for e in st:
    if e == delim:
      result.add sub
      sub.setLen 0
    else:
      sub.add e
  result.add sub

proc joins*[T](sst: seq[seq[T]], delim: T): seq[T] =
  ## Return joined seq of sub-seqs splittable by ``delim``.
  ## E.g. ``@[@["a"], @["b", "c"]].joins("--") == @["a", "--", "b", "c"].``
  let last = sst.len - 1
  for i, st in sst:
    result = result & st
    if i != last:
      result.add delim
