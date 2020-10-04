import ./mfile, std/parseutils
from std/strutils import nil

proc fileEq*(pathA, pathB: string): bool =
  ## Compare whole file contents given paths. Returns true if and only if equal.
  let fA = mopen(pathA)
  if fA.mem == nil:
    return false
  let fB = mopen(pathB)
  if fB.mem == nil:
    return false
  if fA.len == 0 and fB.len == 0:
    return true       #Can mmap give non-nil mem for 0size on any OS?
  result = fA == fB
  fA.close()
  fB.close()

proc parseIx*(ixSpec: string, sz: int, x: var int): int =
  ## Apply index specification against a size to get integer index.  Returns
  ## bytes of string parsed.
  var xf: float
  var rest = parseFloat(ixSpec, xf, 0)
  if rest < ixSpec.len and ixSpec[rest] == '%':
    inc(rest)
    xf *= 0.01
  if -1 < xf and xf < 0:
    xf += 1
  if 0 < xf and xf < 1:
    x = int(xf * float(sz))
  elif xf < 0:
    x = sz + int(xf)
  else:
    x = int(xf)
  x = max(0, x)               #clip s.t. 0 <= x <= sz
  x = min(x, sz)
  return rest

proc parseSlice*(slcSpec: string, sz: int; a, b: var int) =
  ## Apply slice specification against a size to get index range [a,b).  Syntax
  ## is `[a][%][:[b[%]]]`, like Python but w/optional '%'.  If "a"|"b" are on
  ## (0,1) their amount is a size fraction even without '%'.  a==b => empty.
  a = 0
  b = sz
  if slcSpec.len == 0:
    return
  var rest = parseIx(slcSpec, sz, a)
  if rest < slcSpec.len and slcSpec[rest] == ':':
    inc(rest)
    if rest < slcSpec.len:
      discard parseIx(slcSpec[rest .. ^1], sz, b)
    else:
      discard
  else:
    b = a

proc parseSlice*(s: string): tuple[a, b: int] =
  ## Parse ``[a][:][b]``-like Python index/slice specification.
  result[0] = 0
  result[1] = result[1].high
  if s.len == 0:
    return
  let fs = strutils.split(s, ':')
  if fs.len == 1:
    discard parseInt(s, result[0])
    result[1] = result[0] + 1
    return
  if fs.len == 2:
    if fs[0].len > 0: discard parseInt(fs[0], result[0])
    if fs[1].len > 0: discard parseInt(fs[1], result[1])

when isMainModule:
  var a, b: int
  template testIt(str: string) {.dirty.} =
    parseSlice(str, 50, a, b)
    echo "size50: str: \"", str, "\" -> [", a, ", ", b, ")"
  testIt("20")    ; testIt(":10")    ; testIt("10:")    ; testIt("10:40")
  testIt("-20")   ; testIt(":-10")   ; testIt("-10:")   ; testIt("-40:-10")
  testIt("20%")   ; testIt(":10%")   ; testIt("10%:")   ; testIt("10%:40%")
  testIt("0.20")  ; testIt(":0.10")  ; testIt("0.10:")  ; testIt("0.10:0.40")
  testIt("-20%")  ; testIt(":-10%")  ; testIt("-10%:")  ; testIt("-40%:-10%")
  testIt("-0.20") ; testIt(":-0.10") ; testIt("-0.10:") ; testIt("-0.40:-0.10")
  testIt("55")    ; testIt("55:")    ; testIt(":55")
  testIt("-55")   ; testIt("-55:")   ; testIt(":-55")
  testIt("")      ; testIt("non-numeric")
