type csize = uint
proc `:=`*[T](x: var T, y: T): T =
  ## A assignment expression like convenience operator
  x = y
  x

proc findUO*(s: string, c: char): int {.noSideEffect.} =
  proc memchr(s: pointer, c: char, n: csize): pointer {.importc:"memchr",
                                                        header:"<string.h>".}
  let p = memchr(s.cstring.pointer, c, s.len.csize)
  if p == nil: -1 else: (cast[uint](p) - cast[uint](s.cstring.pointer)).int

proc delete*(x: var string, i: Natural) {.noSideEffect.} =
  ## Just like ``delete(var seq[T], i)`` but for ``string``.
  let xl = x.len
  for j in i.int .. xl-2: shallowCopy(x[j], x[j+1])
  setLen(x, xl-1)

iterator maybePar*(parallel: bool, a, b: int): int =
  ## if flag is true yield `` `||`(a,b) `` else ``countup(a,b)``.
  if parallel:
    for i in `||`(a, b): yield i
  else:
    for i in a .. b: yield i

import macros

macro enumerate*(x: ForLoopStmt): untyped =
  ## Generic enumerate macro
  expectKind x, nnkForStmt
  result = newStmtList()
  result.add newVarStmt(x[0], newLit(0))
  var body = x[^1]
  if body.kind != nnkStmtList:
    body = newTree(nnkStmtList, body)
  body.add newCall(bindSym"inc", x[0])
  var newFor = newTree(nnkForStmt)
  for i in 1..x.len-3:
    newFor.add x[i]
  newFor.add x[^2][1]
  newFor.add body
  result.add newFor

proc postInc*(x: var int): int =
  ##Similar to post-fix ``++`` in C languages: yield initial val, then increment
  result = x
  inc(x)

proc delItem*[T](x: var seq[T], item: T): int =
  result = find(x, item)
  if result >= 0:
    x.del(Natural(result))
