import std/[strutils, sets, strformat]

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

proc commentStrip*(s: string): string =
  ## return string with any pre-'#' whitespace and any post-'#' text removed.
  if s.startsWith("#"): return          # implicit ""
  if (let ix = s.find('#'); ix > 0):
    for i in countdown(ix - 1, 0):
      if s[i] notin Whitespace:
        result = s[0..i]
        break
  else: result = s

from math import floor, log10, isnan  #*** FORMATTING UNCERTAIN NUMBERS ***
const pmUnicode* = "±"                  ## for re-assign/param passing ease
const pmUnicodeSpaced* = " ± "          ## for re-assign/param passing ease
var pmDfl* = " +- "                     ## how plus|minus is spelled

func sciNoteSplits(f: string; d, e: var int) {.inline.} =
  for i in 0 ..< f.len:         # +-D.DD*e+-NN -> ('.' dec.index, 'e' exp.index)
    if   f[i] == '.': d = i     # Either d|e == 0 => parse error.
    elif f[i] == 'e': e = i; break

proc fmtUncertainRound*(val, err: float, sigDigs=2): (string, string) =
  ## Format `err` to `sigDigs` (in ffScientific mode); then format `val` such
  ## that the final decimal place of the two always matches.  E.g., (3141.5..,
  ## 34.56..) => ("3.142e+03", "3.5e+01").  While useful on its own to suppress
  ## noise digits, it is also a building block for nicer formats.  This is the
  ## only rounding guaranteeing numbers re-parse into floats.
  when isMainModule: (if pmDfl.len==0: return) # give sideEffect for proc array
  if abs(err) == 0.0 or err.isnan:      # cannot do much here
    result[0].formatValue(val, ".016e")
    result[1].formatValue(err, ".016e"); return
  let sigDigs = sigDigs - 1             # adjust to number after '.' in sciNote
  result[1].formatValue(err, ".0" & $sigDigs & "e")
  var d, e: int
  result[1].sciNoteSplits d, e
  if e == 0:                            # [+-]inf err => 0|self if val infinite
    if abs(val / err) < 1e-6: result[0] = "0.e0"
    else: result[0].formatValue(val, ".016e")
    return
  var places = val.abs.log10.floor.int - (parseInt(result[1][e+1..^1])-(e-d-1))
  if places < 0:  # statistical 0 ->explict
    if val.isnan or val*0.5 == val: result[0].formatValue(val, ".016e")
    else: result[0] = "0.e0"
  else:
    result[0].formatValue(val, ".0" & $places & "e")
# Trickiness here is that `val` may be rounded up to next O(magnitude) as part
# of ffScientific, shifting by 1 place.  Bumping `places` might BLOCK round up,
# BUT when this happens we can just add a '0' if val is being rounded UP.
    result[0].sciNoteSplits d, e
    if d > 0 and e > 0:
      if abs(parseFloat(result[0])) > abs(val) and result[0][e-1] in {'.', '0'}:
        result[0] = result[0][0..<e] & "0" & result[0][e..^1]

proc addShifted(result: var string; sciNum: string; shift,decPtIx,expIx: int) =
  if shift < 0:     # NOTE: This only adds a shifted mantissa, not the exponent
    if sciNum[0] in {'+', '-'}:
      result.add sciNum[0]
    result.add "0." & '0'.repeat(-shift - 1)    # zeros; adj for always present
    result.add sciNum[decPtIx - 1] & sciNum[decPtIx + 1 ..< expIx]
  elif shift > 0:                   # X.YYYeN->XYYY000 w/new '.' maybe in there
    result.add sciNum[0..<decPtIx]
    let newDecIx = decPtIx + shift
    if shift < expIx - decPtIx:     # internal decimal
      result.add sciNum[decPtIx + 1 ..< newDecIx + 1]
      result.add '.'
      result.add sciNum[newDecIx + 1 ..< expIx]
    else:                           # All dig before decimal; maybe zeros at end
      result.add sciNum[decPtIx + 1 ..< expIx]
      result.add '0'.repeat(newDecIx - expIx + 1)
      result.add '.'
  else:
    result.add sciNum[0..<expIx]

proc fmtUncertainSci(val, err: string, sigDigs=2, pm=pmDfl, exp=true): string =
  var dV, eV, dU, eU: int       # (Value, Uncertainty)*(decPtIx, expIx)
  val.sciNoteSplits dV, eV      # diff of exponent *positions* is decimal shift
  err.sciNoteSplits dU, eU      # up to leading - in `val`.
  if dV == 0 or eV == 0 or dU == 0 or eU == 0:    # nan|inf in val|err
    return "(" & val & pm & err & ")"
  let negAdj = if val[0] == '-': 1 else: 0
  result = newStringOfCap(val.len*2 + pm.len - 2) # maybe 1 extra if val < 0
  result.add "(" & val[0..<eV] & pm
  result.addShifted err, eU - eV + negAdj, dU, eU # neg/right shift|no shift
  result.add ")"
  if exp: result.add val[eV..^1]

proc fmtUncertainSci*(val, err: float, sigDigs=2, pm=pmDfl): string =
  ## format as (val +- err)e+NN with err to `sigDigs` and same final decimal.
  let (val, err) = fmtUncertainRound(val, err, sigDigs)
  fmtUncertainSci(val, err, sigDigs, pm)

proc fmtUncertain*(val, err: float, sigDigs=3, pm=pmDfl,
                   eLow = -2, eHigh = 3): string =
  ## This is printf-%g/gcvt-esque but allows callers to customize how near 0 the
  ## *uncertainty-rounded val exponent* must be to get non-scientific notation
  ## (& also formats both a number & its uncertainty like `fmtUncertainSci`).
  let (val, err) = fmtUncertainRound(val, err, sigDigs)
  var dV, eV, dU, eU: int               # (Value, Uncertainty)*(decPtIx, expIx)
  val.sciNoteSplits dV, eV              # duplicative, but (relatively) cheap
  if dV == 0 or eV == 0:
    return "(" & val & pm & err & ")"
  let exp = parseInt(val[eV+1..^1])     # order-of-magnitude of val
  let negAdj = if val[0] == '-': 1 else: 0
  if exp == 0:                          # no shift; drop zero exp & strip parens
    result = fmtUncertainSci(val, err, sigDigs, pm, exp=false)[1..^2]
  elif eLow <= exp and exp <= eHigh:    # shift right | left
    result.addShifted val, exp, dV, eV
    if result[^1] == '.': result.setLen result.len - 1
    result.add pm
    err.sciNoteSplits dU, eU            # duplicative, but (relatively) cheap
    let shift = exp - (eV - negAdj - eU)
    result.addShifted err, shift, dU, eU
    if result[^1] == '.': result.setLen result.len - 1
  else:                                 # too small/too big: sci notation
    result = fmtUncertainSci(val, err, sigDigs, pm)

when isMainModule:
  from math import sqrt                 # for -nan; dup import is ok
  proc rnd(v, e: float; sig=2): string =  # Create 3 identical signature procs
    let (v,e) = fmtUncertainRound(v, e, sig); v & "   " & e
  proc sci(v, e: float; sig=2): string = fmtUncertainSci(v, e, sig)
  proc aut(v, e: float; sig=2): string = fmtUncertain(v, e, sig)

  for k, nmFmt in [("ROUND", rnd), ("SCI", sci), ("AUTO", aut)]:
    let fmt = nmFmt[1]
    if k != 0: echo ""
    echo nmFmt[0]
    for j, p in [2, 3]:           # This all works with/without dragonbox
      if j != 0: echo ""; echo ""
      for i, sd in [ 1.23456e-6, 9.9996543, 1234.56, 99996.543 ]:
        if i != 0: echo ""
        echo "+1.2345678e-5 ", sd, "\t\t", fmt(+1.2345678e-5, sd, p)
        echo "+12.34567890  ", sd, "\t\t", fmt(+12.34567890 , sd, p)
        echo "+123.4567890  ", sd, "\t\t", fmt(+123.4567890 , sd, p)
        echo "+9.432101234  ", sd, "\t\t", fmt(+9.432101234 , sd, p)
        echo "+9.987654321  ", sd, "\t\t", fmt(+9.987654321 , sd, p)
        echo "-1.2345678e-5 ", sd, "\t\t", fmt(-1.2345678e-5, sd, p)
        echo "-12.34567890  ", sd, "\t\t", fmt(-12.34567890 , sd, p)
        echo "-123.4567890  ", sd, "\t\t", fmt(-123.4567890 , sd, p)
        echo "-9.432101234  ", sd, "\t\t", fmt(-9.432101234 , sd, p)
        echo "-9.987654321  ", sd, "\t\t", fmt(-9.987654321 , sd, p)
  echo "\nSPECIALS FP VALUES:"
  let minf = -1.0/0.0
  let pinf = +1.0/0.0
  let mnan = sqrt(-1.0)
  let pnan = log10(-1.0)
  for i, nmFmt in [("ROUND", rnd), ("SCI", sci), ("AUTO", aut)]:
    let fmt = nmFmt[1]
    if i != 0: echo ""
    echo nmFmt[0]
    for v in [minf, pinf, mnan, pnan, 1.0]:
      for e in [minf, pinf, mnan, pnan, 1.0]:
        echo v, " ", e, "\t\t", fmt(v, e, 2)
