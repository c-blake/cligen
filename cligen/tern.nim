##This module implements a Ternary Search Tree which is an efficient container
##for a sorted set|mapping of strings in the family of digital search trees.
##Presently, NUL bytes(``'\0'``) are not allowed in keys.  I have measured it as
##up to 1.5x faster than ``CritBitTree`` (at a cost of a 7x memory footprint)
##doing things like unique `**.nim` lines and never more than 1.1x slower.  It
##mostly felt easier for me to extend this variant.  It is API-compatible with
##``CritBitTree`` (except a ``longestMatch`` -> ``longest`` parameter rename
##which will be trapped by the compiler if you use kwargs).  ``CritBitTree``
##itself is API-compatible with the union of both ``HashSet`` and ``Table``.
import std/algorithm, ./sysUt # reverse, postInc

const NUL* = '\0'
type
  NodeOb*[T] {.acyclic.} = object
    ch*: char
    cnt*: int
    when T isnot void:
      val*: T
    kid*: array[3, ref NodeOb[T]]   #0,1,2 ~ <,=,>
  Node*[T] = ref NodeOb[T]
  Tern*[T] = object   ## A Tern can be used as either a mapping from strings
                      ## to type ``T`` or as a set(strings) if ``T`` is void.
    root*: Node[T]
    count: int        ## Number of elements
    depth: int        ## Depth of Tree

proc len*[T](t: Tern[T]): int {.inline.} = t.count

proc rawGet*[T](t: Tern[T], key: string): Node[T] =
  ## Return node for ``key`` or ``nil`` if not found
  var i = 0
  var p = t.root
  while p != nil:
    let c = if i < key.len: key[i] else: NUL
    let d = cmp(c, p.ch)
    if d == 0 and i.postInc == key.len:
      return p
    p = p.kid[d+1]

proc rawPfx*[T](t: Tern[T], pfx: string, longest=false): Node[T] =
  ## Return sub-tree for all keys starting with `prefix` or if ``longest``
  ## then sub-tree for longest match (which need not be a complete match).
  var i = 0                   #XXX do longest
  var p = t.root
  while p != nil and i < pfx.len:
    let d = cmp(pfx[i], p.ch)
    if d == 0:
      i.inc
      if i == pfx.len:
        return if p != nil: p.kid[1] else: p
    p = p.kid[d+1]
  if p != nil: p.kid[1] else: p

proc rawInsert*[T](t: var Tern[T], key: string): Node[T] =
  var depth = 1
  var i = 0
  var p = t.root.addr
  while p[] != nil:
    let c = if i < key.len: key[i] else: NUL
    let d = cmp(c, p[].ch)
    if d == 0 and i.postInc == key.len:
      return p[]
    if d == 0: p.cnt.inc
    p = p.kid[d+1].addr
    depth.inc
  while true:
    var n: Node[T]; new n
    n.ch = if i < key.len: key[i] else: NUL
    p[] = n
    if i.postInc == key.len:
      p.cnt = 1
      t.depth = max(t.depth, depth)
      t.count.inc
      return n
    p.cnt.inc
    p = p.kid[1].addr
    depth.inc
#XXX Implement excl/delete/remove someday

#[from strutils import nil
proc print*[T](p: Node[T], depth=0) = #2,1,0 gives std emoji-orientation
  if p == nil: return                 #..i.e. ":-)" head-tilt not "(-:".
  print(p.kid[2], depth + 1)
  echo strutils.repeat("  ", depth),cast[int](p)," ch: '",p.ch,"' cnt: ",p.cnt
  print(p.kid[1], depth + 1)
  print(p.kid[0], depth + 1)
proc echoKeys*[T](p: Node[T], pfx="", key="") =
  if p == nil: return
  ecKeys(p.kid[0], pfx, key)
  if p.ch == NUL: echo pfx, key
  else: ecKeys(p.kid[1], pfx, key & $p.ch)
  ecKeys(p.kid[2], pfx, key) ]#
iterator leaves[T](r: Node[T], depth:int, pfx=""): tuple[k:string, n:Node[T]] =
  type                                               #Nim iterators should grow
    Which = enum st0, st1, st2, stR                  #..recursion capability so
    State = tuple[st: Which, k: string, n: Node[T]]  #..this headache can be as
  if r != nil:                                       #..easy as echoKeys above.
    var stack = newSeqOfCap[State](depth)
    stack.add (st: st0, k: pfx, n: r)
    while stack.len > 0:
      let state = stack[^1].addr
      if state.n == nil: break
      case state.st
      of st0:
        state.st = st1
        if state.n.kid[0] != nil:
          stack.add (st: st0, k: state.k, n: state.n.kid[0])
      of st1:
        state.st = st2
        if state.n.ch == NUL:
          yield (k: state.k, n: state.n)
        elif state.n.kid[1] != nil:
          stack.add (st: st0, k: state.k & $state.n.ch, n: state.n.kid[1])
      of st2:
        state.st = stR
        if state.n.kid[2] != nil:
          stack.add (st: st0, k: state.k, n: state.n.kid[2])
      of stR: discard stack.pop

# From here until `$` is really the same for many kinds of search tree.
proc contains*[T](t: Tern[T], key: string): bool {.inline.} =
  rawGet(t, key) != nil

template get[T](t: Tern[T], key: string): T =
  let n = rawGet(c, key)
  if n == nil:
    raise newException(KeyError, "key not found: " & $key)
  n.val

proc `[]`*[T](t: Tern[T], key: string): T {.inline.} =
  ## Retrieves value at ``t[key]`` or raises ``KeyError`` if missing.
  get(t, key)

proc `[]`*[T](c: var Tern[T], key: string): var T {.inline.} =
  ## Retrieves modifiable value at ``t[key]`` or raises ``KeyError`` if missing.
  get(t, key)

proc mgetOrPut*[T](t: var Tern[T], key: string, val: T): var T =
  ## Retrieves modifiable value at ``t[key]`` or inserts if missing.
  let oldLen = t.len
  var n = rawInsert(t, key)
  when T isnot void:
    n.val = val
    n.val

proc containsOrIncl*[T](t: var Tern[T], key: string, val: T): bool =
  ## Returns true iff ``t`` contains ``key`` or does ``t[key]=val`` if missing.
  let oldLen = t.len
  var n = rawInsert(t, key)
  result = t.len == oldLen
  when T isnot void:
    if not result: n.val = val

proc containsOrIncl*[T](t: var Tern[T], key: string): bool {.discardable.}=
  ## Returns true iff ``t`` contains ``key`` or inserts into ``t`` if missing.
  let oldLen = t.len
  discard rawInsert(t, key)
  result = t.len == oldLen

proc inc*[T](t: var Tern[T], key: string, val: int = 1) =
  ## Increments ``t[key]`` by ``val`` (starting from 0 if missing).
  var n = rawInsert(t, key)
  inc n.val, val

proc incl*(t: var Tern[void], key: string) =
  ## Includes ``key`` in ``t``.
  discard rawInsert(t, key)

proc incl*[T](t: var Tern[T], key: string, val: T) =
  ## Inserts ``key`` with value ``val`` into ``t``, overwriting if present
  var n = rawInsert(t, key)
  n.val = val

proc `[]=`*[T](t: var Tern[T], key: string, val: T) =
  ## Inserts ``key``, ``val``-pair into ``t``, overwriting if present.
  var n = rawInsert(t, key)
  n.val = val

iterator keys*[T](t: Tern[T]): string =
  ## yields all keys in lexicographical order.
  for k, x in t.root.leaves(t.depth): yield k

iterator values*[T](t: Tern[T]): T =
  ## yields all values of `t` in the lexicographical order of the
  ## corresponding keys.
  for k, x in t.root.leaves(t.depth): yield x.val

iterator mvalues*[T](t: var Tern[T]): var T =
  ## yields all values of `t` in the lexicographical order of the
  ## corresponding keys. The values can be modified.
  for k, x in t.root.leaves(t.depth): yield x.val

iterator items*[T](t: Tern[T]): string =
  ## yields all keys in lexicographical order.
  for k, x in t.root.leaves(t.depth): yield k

iterator pairs*[T](t: Tern[T]): tuple[key: string, val: T] =
  ## yields all (key, value)-pairs of `t`.
  for k, x in t.root.leaves(t.depth): yield (k, x.val)

iterator mpairs*[T](t: var Tern[T]): tuple[key: string, val: var T] =
  ## yields all (key, value)-pairs of `t`. The yielded values can be modified.
  for k, x in t.root.leaves(t.depth): yield (k, x.val)

proc `$`*[T](t: Tern[T]): string =
  ## Return string form of ``t``; ``{A,B,..}`` if ``T`` is ``void`` or else
  ## ``{A: valA, B: valB}``.
  if t.len == 0:
    when T is void: result = "{}"
    else: result = "{:}"
  else:
    when T is void:
      const avgItemLen = 8    #A guess is better than nothing
    else:
      const avgItemLen = 16
    result = newStringOfCap(t.len * avgItemLen)
    result.add("{")
    when T is void:
      for key in keys(t):
        if result.len > 1: result.add(", ")
        result.addQuoted(key)
    else:
      for key, val in pairs(t):
        if result.len > 1: result.add(", ")
        result.addQuoted(key)
        result.add(": ")
        result.addQuoted(val)
    result.add("}")

iterator keysWithPrefix*[T](t: Tern[T], prefix: string, longest=false): string =
  ## Yields all keys starting with `prefix`.
  for k, x in rawPfx(t, prefix, longest).leaves(t.depth, prefix):
    yield k

iterator valuesWithPrefix*[T](t: Tern[T], prefix: string, longest=false): T =
  ## Yields all values of ``t`` for keys starting with ``prefix``.
  for k, x in rawPfx(t, prefix, longest).leaves(t.depth, prefix):
    yield x.val

iterator mvaluesWithPrefix*[T](t: var Tern[T], prefix: string,
                               longest=false): var T =
  ## Yields all values of ``t`` for keys starting with ``prefix``.  The values
  ## can be modified.
  for k, x in rawPfx(t, prefix, longest).leaves(t.depth, prefix):
    yield x.val

iterator pairsWithPrefix*[T](t: Tern[T], prefix: string,
                             longest=false): tuple[key: string, val: T] =
  ## Yields all (key, value)-pairs of `t` starting with `prefix`.
  for k, x in rawPfx(t, prefix, longest).leaves(t.depth, prefix):
    yield (k, x.val)

iterator mpairsWithPrefix*[T](t: var Tern[T], prefix: string,
                              longest=false): tuple[key: string, val: var T] =
  ## Yields all (key, value)-pairs of `t` starting with `prefix`.
  ## The yielded values can be modified.
  for k, x in rawPfx(t, prefix, longest).leaves(t.depth, prefix):
    yield (k, x.val)

proc uniquePfxPat*[T](t: Tern[T], key: string, sep="*"): string =
  ## Return shortest unique prefix pattern for ``key`` known to be in ``t``.
  ## Unlike a shortest unique prefix string, this is well-defined for all sets.
  ## The separator character is only used if it can shrink total rendered space.
  var i = 0
  var p = t.root
  while p != nil:
    let c = if i < key.len: key[i] else: NUL
    let d = cmp(c, p.ch)
    if d == 0:
      if p.cnt == 1:
        return if i + 1 + sep.len < key.len: key[0..i] & sep else: key
      i.inc
    p = p.kid[d+1]

proc uniquePfxPats*(x: openArray[string], sep="*"): seq[string] =
  ## Return unique prefixes in ``x`` assuming non-empty-string&unique ``x[i]``.
  result.setLen x.len
  var t: Tern[void]
  for i, s in x: t.incl s
  for i, s in x: result[i] = t.uniquePfxPat(s, sep)

proc uniqueSfxPats*(x: openArray[string], sep="*"): seq[string] =
  ## Return unique suffixes in ``x`` assuming non-empty-string&unique ``x[i]``.
  result.setLen x.len
  var revd = newSeq[string](x.len)
  var t: Tern[void]
  for i, s in x:
    revd[i] = s; revd[i].reverse; t.incl revd[i]
  for i, s in revd:
    result[i] = t.uniquePfxPat(s, "")
    result[i].reverse
    result[i] = sep & result[i]
