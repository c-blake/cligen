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

proc joinS*(sep=" ", a: varargs[string, `$`]): string =
  ## Join after `$`.  `S` is intended to suggest `$`. `echo " ".joinS(a, b, c)`
  ## is more ceremony than `print` but may also have broader utility.
  for i, x in pairs(a):
    if i != 0: result.add sep
    result.add $x

proc commentStrip*(s: string): string =
  ## return string with any pre-'#' whitespace and any post-'#' text removed.
  if s.startsWith("#"): return          # implicit ""
  if (let ix = s.find('#'); ix > 0):
    for i in countdown(ix - 1, 0):
      if s[i] notin Whitespace:
        result = s[0..i]
        break
  else: result = s

from cligen/mslice import pow10
from math import isNaN, `^`, floor, log10, isnan
type f8s {.packed.} = object
  frac {.bitsize: 52}: uint64
  expo {.bitsize: 11}: uint16
  sign {.bitsize:  1}: uint8

func abs(x: float): float {.inline.} =
  var x: f8s = cast[ptr f8s](x.unsafeAddr)[]
  x.sign = 0
  cast[ptr float](x.addr)[]

func expo(x: float): int {.inline.} =
  int(cast[ptr f8s](x.unsafeAddr)[].expo) - 1023

func ceilLog10(x: float): int {.inline.} =
  # Give arg to pow10 such that `abs(x)*pow10[1-arg]` is on half-open `[1,10)`.
  if x == 0: return 0           # FPUs basically take ceil(log_2(x)) for us.
  result = int(0.30102999566398119521 * float(x.expo + 1))
  if x > 1: inc result          # Already done here like 86% of the time
  let leadingDig = int(x * pow10[1 - result])
  if leadingDig == 0:           # Want leading digit on [1,10)
    dec result
  if x == pow10[result - 1]:    # Exact powers of 10 need 1 more `dec result`..
    dec result                  #..BUT also get leadingDig == 1.  So, cmp

let zeros = repeat('0', 308)

func decimalDigitTuples*(n=2): string =
  for i in 0 ..< 10^n:
    let iStr = $i
    result.add repeat('0', n - iStr.len)
    result.add iStr

const d3 = decimalDigitTuples(3)        # Global so usable by ecvt for exponents
func uint64toDecimal*(res: var openArray[char], x: uint64): int =
  ## Flexible oA[char] inp; Fast 3B outp at a time; Answer is `res[result..^1]`.
  var num = x                           # On AMD/Intel perf d3 ~same as `d2`
  result = res.len - 1                  #.. (PGO moving either +-1.2x); d3 is
  while num >= 1000:                    #.. consistently faster on ARM & also
    let originNum = num                 #.. simplifies handling exponents.  L1
    num = num div 1000                  #.. more likely to grow than faster div
    let index = 3*(originNum - 1000*num)
    res[result    ] = d3[index + 2]
    res[result - 1] = d3[index + 1]
    res[result - 2] = d3[index    ]
    dec result, 3
  if num < 10:          # process last 1 digit
    res[result] = chr(ord('0') + num)
  elif num < 100:       # process last 2 digits
    let index = num * 3
    res[result    ] = d3[index + 2]
    res[result - 1] = d3[index + 1]
    dec result
  else:                 # process last 3 digits
    let index = num * 3
    res[result    ] = d3[index + 2]
    res[result - 1] = d3[index + 1]
    res[result - 2] = d3[index    ]
    dec result, 2

## DragonBox is fast & accurate but sadly has no output format flexibility.
## Someday that may improve.  For now the below routines maintain speed but fill
## the flexibility gap at a tiny loss of accuracy.  This is not so bad if your
## mindset is that output (&parsing) is just another calculation on floats like
## transcendentals.  1 ULP is often considered ok for those.  Rel.err. < ~2^-52
## for me.  Binary|C99 hex float are cheaper marshaling & Javascript should just
## learn C99 hex floats already, especially since every number is `float`!
## `ecvt`/`fcvt` can be ~2X faster than DragonBox when asking for rounded
## results/fewer digits which for me is a common case.
type
  FloatCvtOptions* =  ## The many options of binary -> string float conversion.
    enum fcPad0,      ## Pad with '0' to the right (based upon precision `p`)
         fcCapital,   ## Use E|INF|NAN not default e|inf|nan
         fcPlus,      ## Leading '+' for positive numbers, not default ""
         fcTrailDot,  ## Trailing '.' for round integers (to signify "FP")
         fcTrailDot0, ## Trailing ".0" for round integers; overrides fcTrailDot
         fcExp23,     ## 2|3 digit exp; 1e03 or 1e103 not 1e3; only for ecvt
         fcExp3,      ## 3 digit exp; 1e003 not 1e3; only for ecvt
         fcExpPlus    ## '+' on positive exponents; 1e+3 not 1e3; only for ecvt

template efCvtNaNinf(s, x, xs, opts) =
  s.setLen 0
  var xs: f8s = cast[ptr f8s](x.unsafeAddr)[]
  if xs.sign == 1: s.add '-'
  elif fcPlus in opts: s.add '+'
  xs.sign = 0
  if isNaN(x):                      # First deal with +-(NaN|Inf)
    s.add (if fcCapital in opts: "NAN" else: "nan")
    return
  let x = cast[ptr float](xs.addr)[]
  if x > 1.7976931348623157e308:    # -ffast-math may need -fno-finite-math-only
    s.add (if fcCapital in opts: "INF" else: "inf")
    return                          # Ok; Now finite numbers

proc ecvt*(s: var string, x: float, p=17, opts={fcPad0}) {.inline.} =
  ## ANSI C/Unix ecvt: float -> D.PPPPe+EE; Most conversion in int arithmetic.
  ## Accurate to ~52 bits with p=17.
  efCvtNaNinf(s, x, xs, opts)           # `return`s for non-finite numbers
  var i = s.len
  s.setLen i + p + 70                   # easy bound: D.Pe-EEE=2+p+5 = p+7 B
  var decs {.noinit.}: array[24, char]
  var e = int(0.30102999566398119521 * float(x.expo + 1))
  if x == 0: e = 0
  if x > 1: inc e
  var dig = uint64(x*pow10[1 - e])      # leading digit D
  if dig == 0:                          # Want leading digit on [1,10)
    dec e; dig = uint64(x*pow10[1 - e]) # ceilLog10 inline avoids ~85% re-do's
  if x == pow10[e - 1]:                 # Exact pows of 10 need 1 more `dec e`..
    dec e                               #..BUT also get leadingDig==1.  So, cmp
  let scl = x*pow10[1 - e]
  var n0R = 0; var i0 = 0; var nDec = 0
  var p = p
  if p > 18:                            # clip precision to 18
    n0R = p - 18
    p   = 18                            # 64 bits==19 decs but sgn & round trick
  let frac = uint64((scl - dig.float)*pow10[p] + 0.5)
  if frac.float >= pow10[p]:            # 9.99 with prec 1 rounding up
    inc dig
  elif frac != 0:                       # post decimal digits to convert
    i0 = uint64toDecimal(decs, frac)
    nDec = 24 - i0
  if dig > 9: dig = 1; inc e            # perfect 10.0 scl can occur; adjust
  s[i] = chr(ord('0') + dig); inc i     # format D
  if p > 0:                             # format .PPP => '.'&lead0&digits&trail0
    s[i] = '.'; inc i
    copyMem s[i].addr, zeros[0].unsafeAddr, min(zeros.len, p - nDec)
    copyMem s[i + p - nDec].addr, decs[i0].addr, nDec
    if fcPad0 in opts: inc i, p
    else: s.setLen i + p; i = 1 + s.rfind({'1'..'9', '.'}); s.setLen i + 5
  elif fcTrailDot0 in opts: s[i] = '.'; s[i+1] = '0'; inc i, 2
  elif fcTrailDot in opts: s[i] = '.'; inc i
  s[i] = (if fcCapital in opts: 'E' else: 'e'); inc i
  dec e                                 # adjust for first digit on [1,10)
  template eSign =
    if e < 0: s[i] = '-'; e = -e; inc i
    elif fcExpPlus in opts: s[i] = '+'; inc i
  if fcExp23 in opts:                   # Nums with >2 dig exps can be rare
    eSign
    if   e < 10 : s[i] = '0'      ; s[i+1] = chr(ord('0') + e); inc i, 2
    elif e < 100: s[i] = d3[3*e+1]; s[i+1] = d3[3*e + 2]; inc i, 2
    else      : s[i] = d3[3*e]; s[i+1] = d3[3*e+1]; s[i+2] = d3[3*e+2]; inc i, 3
  elif fcExp3 in opts:                  # Folks can want same .len guarantees
    eSign
    if   e < 10 : s[i] = '0'    ; s[i+1] = '0'      ; s[i+2] = chr(ord('0') + e)
    elif e < 100: s[i] = '0'    ; s[i+1] = d3[3*e+1]; s[i+2] = d3[3*e + 2]
    else        : s[i] = d3[3*e]; s[i+1] = d3[3*e+1]; s[i+2] = d3[3*e+2]
    inc i, 3
  else:                                 # but many times 1e-9..1e9 is fine
    eSign
    if   e < 10 : s[i] = chr(ord('0') + e); inc i
    elif e < 100: s[i] = d3[3*e+1]; s[i+1] = d3[3*e + 2]; inc i, 2
    else        : s[i] = d3[3*e]; s[i+1] = d3[3*e+1]; s[i+2] = d3[3*e+2]; inc i, 3
  s.setLen i

proc fcvt*(s: var string, x: float, p: int, opts={fcPad0}) {.inline.} =
  ## ANSI C/Unix fcvt: float -> DDD.PPPP; Most conversion in integer arithmetic.
  ## Accurate to ~52 bits with p=17.
  efCvtNaNinf(s, x, xs, opts)           # `return`s for non-finite numbers
  var decs {.noinit.}: array[24, char]
  let clX = ceilLog10(x)                # already +1 over C nDecimals
  var p10 = p
  var nI  = max(0, clX)                 # integer/pre-decimal digits
  var n0R = 0
  if clX + p > 18:                      # Need 0-fill in integer part
    n0R = clX + p - 18
    dec p10, n0R
  let round = uint64(x*pow10[p10] + 0.5)
  let i0 = uint64toDecimal(decs, round) # All non-0 decimal digits in the answer
  let nDec = 24 - i0
  if round == 0: n0R = p                # 0.p0s
  var n0 = min(-clX, p - 1)
  if nDec > clX + p:                    # 999.9 -> 1000
    inc n0R
    if clX > -1: inc nI
    else       : dec n0
  var i = s.len
  s.setLen 4 + max(0, n0) + 24 - i0 + n0R
  copyMem s[i].addr, decs[i0].addr, nI; inc i, nI
  if p > 0:
    if nI == 0: s[i] = '0'; inc i       # leading '0.' for pure fractions
    s[i] = '.'; inc i
    if n0 > 0:
      copyMem s[i].addr, zeros[0].unsafeAddr, min(zeros.len, n0); inc i, n0
    copyMem s[i].addr, decs[i0 + nI].addr, 24 - (i0 + nI)
    inc i, 24 - (i0 + nI)
    if fcPad0 in opts: copyMem s[i].addr,zeros[0].unsafeAddr, n0R; inc i,n0R
    else: s.setLen i; i = 1 + s.rfind({'1'..'9', '.'})
  elif fcTrailDot0 in opts: s[i] = '.'; s[i+1] = '0'; inc i, 2
  elif fcTrailDot in opts: s[i] = '.'; inc i
  s.setLen i
                                      #*** FORMATTING UNCERTAIN NUMBERS ***
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

proc fmtUncertainMergedSci(val, err: string, sigDigs=2, exp=true): string =
  var dV, eV, dU, eU: int       # (Value, Uncertainty)*(decPtIx, expIx)
  val.sciNoteSplits dV, eV      # diff of exponent *positions* is decimal shift
  err.sciNoteSplits dU, eU      # up to leading - in `val`.
  if dV == 0 or eV == 0 or dU == 0 or eU == 0:    # nan|inf in val|err
    return val & "(" & err & ")"
  result = newStringOfCap(val.len + sigDigs + 2)
  result.add val[0..<eV]
  if result[^1] == '.': result.setLen result.len - 1
  result.add '('
  result.add err[0..<dU] & err[dU+1..<eU]
  result.add ')'
  if exp: result.add val[eV..^1]

proc fmtUncertainMergedSci*(val, err: float, sigDigs=2): string =
  ## Format in "Particle Data Group" Style with uncertainty digits merged into
  ## the value and also in scientific-notation: val(err)e+NN with `sigDigs` of
  ## error digits.  E.g. "12.34... +- 0.56..." => "1.234(56)e+01" (w/sigDigs=2).
  let (val, err) = fmtUncertainRound(val, err, sigDigs)
  fmtUncertainMergedSci(val, err, sigDigs)

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
  ## Format as (val +- err)e+NN with err to `sigDigs` and same final decimal.
  let (val, err) = fmtUncertainRound(val, err, sigDigs)
  fmtUncertainSci(val, err, sigDigs, pm)

proc fmtUncertain*(val, err: float, sigDigs=2, pm=pmDfl,
                   eLow = -2, eHigh = 4): string =
  ## This is printf-%g/gcvt-ish but allows callers to customize (eLow,eHigh) how
  ## near 0 an *uncertainty-rounded val exponent* can be to get non-scientific
  ## notation & formats a number & its uncertainty like `fmtUncertainSci`.
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

proc fmtUncertainMerged*(val,err: float, sigDigs=2, eLow = -2, eHigh=4): string=
  ## This is printf-%g/gcvt-ish but allows callers to customize (eLow,eHigh) how
  ## near 0 an *uncertainty-rounded val exponent* can be to get non-scientific
  ## notation & formats a number & its uncertainty like `fmtUncertainMergedSci`.
  let (val, err) = fmtUncertainRound(val, err, sigDigs)
  var dV, eV, dU, eU: int               # (Value, Uncertainty)*(decPtIx, expIx)
  val.sciNoteSplits dV, eV              # duplicative, but (relatively) cheap
  if dV == 0 or eV == 0:
    return val & "(" & err & ")"
  let exp = parseInt(val[eV+1..^1])     # order-of-magnitude of val
  if exp == 0:                          # no shift; drop zero exp
    result = fmtUncertainMergedSci(val, err, sigDigs, exp=false)
  elif eLow <= exp and exp <= eHigh:    # shift right | left
    result.addShifted val, exp, dV, eV
    if result[^1] == '.': result.setLen result.len - 1
    result.add '('
    err.sciNoteSplits dU, eU            # duplicative, but (relatively) cheap
    result.add err[0..<dU] & err[dU+1..<eU]
    result.add ')'
  else:                                 # too small/too big: sci notation
    result = fmtUncertainMergedSci(val, err, sigDigs)

when isMainModule:
  from math as m3 import sqrt           # for -nan; dup import is ok
  proc rnd(v, e: float; sig=2): string =  # Create 5 identical signature procs
    let (v,e) = fmtUncertainRound(v, e, sig); v & "   " & e
  proc sci(v, e: float; sig=2): string = fmtUncertainSci(v, e, sig)
  proc aut(v, e: float; sig=2): string = fmtUncertain(v, e, sig)
  proc msc(v, e: float; sig=2): string = fmtUncertainMergedSci(v, e, sig)
  proc mau(v, e: float; sig=2): string = fmtUncertainMerged(v, e, sig)

  for k, nmFmt in [("ROUND", rnd), ("SCI", sci), ("AUTO", aut),
                   ("MRGSCI", msc), ("MRGAUTO", mau)]:
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

  var s: string # test drive float formatting
  template doEchD(cvt, x, p) = cvt s, x, p; echo s
  template doEcho(cvt, x, p, opts) = cvt s, x, p, opts; echo s
  echo "\e[7mdefault fcvt; p = 10\e[m"
  doEchD fcvt, 1.234, 10
  doEchD fcvt,-4.25 , 10
  doEchD fcvt, 8.5  , 10
  echo "\n\e[7mempty fcvt opts (p=17, no Pad0)\e[m"
  doEcho fcvt, 1.1  , 17, {}
  doEcho fcvt,-4.25 , 17, {}
  doEcho fcvt, 8.5  , 17, {}
  echo "\n\e[7m0 prec trailDot*\e[m"
  doEcho fcvt, 8.0  ,  0, {}
  doEcho fcvt, 8.0  ,  0, {fcTrailDot}
  doEcho fcvt, 8.0  ,  0, {fcTrailDot0}
  echo "\n\e[7mfcPlus, p=9\e[m"
  doEcho fcvt, 1.234,  9, {fcPlus}
  doEcho fcvt,-4.25 ,  9, {fcPlus}
  doEcho fcvt, 8.5  ,  9, {fcPlus}
  echo "\n\e[7mdefault ecvt\e[m"
  doEchD ecvt, 1.234e101, 15
  doEchD ecvt,-4.25e10  , 15
  doEchD ecvt, 8.5e1    , 15
  echo "\n\e[7mempty ecvt opts (no Pad0)\e[m"
  doEcho ecvt, 1.234e101, 15, {}
  doEcho ecvt,-4.25e10  , 15, {}
  doEcho ecvt, 8.5e1    , 15, {}
  echo "\n\e[7mExp23\e[m"
  doEcho ecvt, 1.234e101, 15, {fcExp23}
  doEcho ecvt,-4.25e10  , 15, {fcExp23}
  doEcho ecvt, 8.5e1    , 15, {fcExp23}
  echo "\n\e[7mExp23+\e[m"
  doEcho ecvt, 1.234e101, 15, {fcExp23, fcExpPlus}
  doEcho ecvt,-4.25e10  , 15, {fcExp23, fcExpPlus}
  doEcho ecvt, 8.5e1    , 15, {fcExp23, fcExpPlus}
  echo "\n\e[7mExp3+, overall +\e[m"
  doEcho ecvt, 1.234e101, 15, {fcPlus, fcExp3, fcExpPlus}
  doEcho ecvt,-4.25e10  , 15, {fcPlus, fcExp3, fcExpPlus}
  doEcho ecvt, 8.5e1    , 15, {fcPlus, fcExp3, fcExpPlus}
  echo "\n\e[7mExp3+, overall +, Pad0 - always same strlen\e[m"
  doEcho ecvt, 1.234e101, 15, {fcPlus, fcPad0, fcExp3, fcExpPlus}
  doEcho ecvt,-4.25e10  , 15, {fcPlus, fcPad0, fcExp3, fcExpPlus}
  doEcho ecvt, 8.5e1    , 15, {fcPlus, fcPad0, fcExp3, fcExpPlus}
  echo "\n\e[7mecvt 0prec\e[m"
  doEcho ecvt, 1.234e101, 0, {}
  doEcho ecvt,-4.25e10  , 0, {}
  doEcho ecvt, 8.5e1    , 0, {}
  echo "\n\e[7mecvt 0prec TrailDot0\e[m"
  doEcho ecvt, 1.234e101, 0, {fcTrailDot0}
  doEcho ecvt,-4.25e10  , 0, {fcTrailDot0}
  doEcho ecvt, 8.5e1    , 0, {fcTrailDot0}
  echo "\n\e[7mecvt 0prec TrailDot\e[m"
  doEcho ecvt, 1.234e101, 0, {fcTrailDot}
  doEcho ecvt,-4.25e10  , 0, {fcTrailDot}
  doEcho ecvt, 8.5e1    , 0, {fcTrailDot}
