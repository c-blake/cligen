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
  ## if flag is true yield ``||(a,b)`` else ``countup(a,b)``.
  if parallel:
    for i in `||`(a, b): yield i
  else:
    for i in a .. b: yield i

import core/macros

macro enumerate*(x: ForLoopStmt): untyped =
  ## Generic enumerate macro; E.g.: ``for i,e in enumerate([3,2,1]): echo i``.
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

when (NimMajor,NimMinor,NimPatch) >= (0,20,0):
  macro toItr*(x: ForLoopStmt): untyped =
    ## Convert factory proc call for inline-iterator-like usage.
    ## E.g.: ``for e in toItr myFactory(parm): echo e``.
    let call = x[^2][1]                   # Get foo out of toItr(foo)
    let itr  = ident"itr"                 # itr = genSym(ident="itr")
    var tree = nnkForStmt.newTree         # for
    for v in x[0 .. x.len-3]: tree.add v  # for v1,...
    tree.add(nnkCall.newTree(itr), x[^1]) # for v1,... in itr(): body
    result = quote do:
      block:
        let `itr` {.inject.} = `call`
        `tree`

proc incd*[T: Ordinal | uint | uint64](x: var T, amt=1): T {.inline.} =
  ##Similar to prefix ``++`` in C languages: increment then yield value
  x.inc amt; x

proc decd*[T: Ordinal | uint | uint64](x: var T, amt=1): T {.inline.} =
  ##Similar to prefix ``--`` in C languages: decrement then yield value
  x.dec amt; x

proc postInc*[T: Ordinal | uint | uint64](x: var T, amt=1): T {.inline.} =
  ##Similar to post-fix ``++`` in C languages: yield initial val, then increment
  result = x; x.inc amt

proc postDec*[T: Ordinal | uint | uint64](x: var T, amt=1): T {.inline.} =
  ##Similar to post-fix ``--`` in C languages: yield initial val, then decrement
  result = x; x.dec amt

proc delItem*[T](x: var seq[T], item: T): int =
  result = find(x, item)
  if result >= 0:
    x.del(Natural(result))
