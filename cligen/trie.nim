##This module implements a Trie, a container for a set|mapping of strings in the
##digital search tree family.  It is drop-in compatible-ish with ``CritBitTree``
##which itself compatible-ish with both ``HashSet`` & ``Table``.  It was easier
##for me to extend this with ``match`` & ``nearLev`` than ``CritBitTree``.

import sets, ./sysUt, algorithm   #HashSet, findUO|findO, :=, reverse
type
  NodeOb[T] {.acyclic.} = object
    term*: bool
    cnt*: uint32
    when T isnot void:
      val*: T
    kidc*: string
    kidp*: seq[ref NodeOb[T]]
  Node*[T] = ref NodeOb[T]
  Trie*[T] = object
    root*: Node[T]
    depth*: int         # Depth of Tree

proc rawPfx[T](t: Trie[T], key: string, i: var int, longest=false): Node[T] =
  var n = t.root
  if n == nil:
    return nil
  var p = n
  for j, ch in key:
    let h = n.kidc.findUO ch
    if h >= 0:
      p = n
      n = n.kidp[h]
    else:
      n = if longest: p else: nil
      break
    i = j + 1
  n

proc rawGet[T](t: Trie[T], key: string): Node[T] =
  var i = 0
  let n = t.rawPfx(key, i)
  if n == nil or not n.term: return nil
  n

proc rawInsert[T](t: var Trie[T], key: string): Node[T] =
  var cntps = newSeqOfCap[ptr uint32](t.depth + key.len)
  var depth = 1
  if t.root == nil:
    t.root = Node[T].new
  var n = t.root
  cntps.add n.cnt.addr        #root node effectively an empty string pfx to all
  var p: Node[T]
  for ch in key:
    let h = n.kidc.findUO ch  #XXX To preserve order add findO returning -iSpot
    if h >= 0:
      p = n.kidp[h]
    else:
      n.kidc.add ch           #XXX .add ==> .insert X -h if in-order with findO
      n.kidp.add (p := Node[T].new)
    depth.inc
    n = p
    cntps.add n.cnt.addr      #just save cnt to update for missing keys
  if not n.term:
    n.term = true
    for cp in cntps: cp[].inc #apply updates
    t.depth = max(t.depth, depth)
  n

proc missingOrExcl*[T](t: var Trie[T], key: string): bool =
  ##``t.excl(key)`` if present in ``t`` and return true else just return false.
  var stack = newSeqOfCap[Node[T]](t.depth)
  var stackH = newSeqOfCap[int](t.depth)
  var n = t.root
  if n == nil:
    return false
  stack.add n
  for ch in key:
    let h = n.kidc.findUO ch
    if h >= 0: n = n.kidp[h]; stack.add n; stackH.add h
    else: return false
  if not stack[^1].term:      #may have only foundk key as a prefix
    return false
  stack[^1].term = false
  for i in countdown(stack.len - 1, 1):
    stack[i].cnt.dec
    if stack[i].cnt == 0:
      stack[i-1].kidc.delete stackH[i-1]
      stack[i-1].kidp.delete stackH[i-1]
  stack[0].cnt.dec
  if stack[0].cnt == 0:
    t.root = nil

proc excl*[T](t: var Trie[T], key: string) =
  ## Remove ``key`` (and any associated value) from ``t`` or do nothing.
  discard t.missingOrExcl key

proc uniquePfxPat*[T](t: Trie[T], key: string, sep="*"): string =
  ## Return shortest unique prefix pattern for ``key`` known to be in ``t``.
  ## Unlike a shortest unique prefix string, this is well-defined for all sets.
  ## ``sep`` is only used if it can shrink total rendered space.
  var n = t.root
  if n == nil or key.len == 0:
    return ""
  for i, ch in key:
    let h = n.kidc.find ch
    if h >= 0:
      n = n.kidp[h]
      if n.cnt == 1:
        return if i + 1 + sep.len < key.len: key[0..i] & sep else: key
    else:
      break

proc match[T](a: var HashSet[string], n: Node[T], pat="", i=0, key: var string,
              a1='?', aN='*', limit=2) =
  if i >= pat.len:
    if n.term and key.len > 0:
      a.incl key
      if a.len >= limit: raise newException(IOError, "done")
    return
  var h: int
  if pat[i] == a1:
    for h, p in n.kidp:
      var key1 = key & n.kidc[h]
      a.match(p, pat, i + 1, key1, a1, aN, limit)
  elif pat[i] == aN:
    var key1 = key
    a.match(n, pat, i + 1, key1, a1, aN, limit)
    if n.kidp.len > 0:
      for h, p in n.kidp:
        var key2 = key & n.kidc[h]
        a.match(p, pat, i, key2, a1, aN, limit)
    elif n.term and i + 1 == pat.len:
      a.incl key
      if a.len >= limit: raise newException(IOError, "done")
  elif (h := n.kidc.findUO(pat[i])) >= 0:
    let p = n.kidp[h]
    key.add n.kidc[h]
    a.match(p, pat, i + 1, key, a1, aN, limit)

proc match*[T](t: Trie[T], pat="", limit=0, a1='?', aN='*'): seq[string] =
  ## Return up to ``limit`` matches of shell [?*] glob pattern ``pat`` in ``t``.
  var key: string
  var s: HashSet[string]
  try: s.match(t.root, pat, 0, key, a1, aN, if limit == 0: t.len else: limit)
  except IOError: discard
  for x in s.items: result.add x  #WTF - items necessary sometimes?

proc nearLevR[T](a: var seq[tuple[d: int, k: string]], n: Node[T], ch: char,
           k: var string, key: string, row0: seq[int], d=0, dmax=2, limit=6) =
  if a.len >= limit: return
  var row = newSeq[int](key.len + 1)
  row[0] = row0[0] + 1                          #col[0]==""
  for j in 1 ..< row.len:                       #Build row
    row[j] = [ row[j-1] + 1, row0[j] + 1, row0[j-1] + (key[j-1] != ch).int ].min
  if row[^1] <= dmax and n.term:                #Last entry is dist
    a.add (row[^1], k[0..<d])
  if row.min <= dmax:                           #Some entry in row cheaper
    for h, ch in n.kidc:                        #..=> need to search kids.
      k[d] = ch
      nearLevR(a, n.kidp[h], ch, k, key, row, d + 1, dmax, limit)

proc nearLev*[T](t: Trie[T], key: string, dmax=1,
                 limit=6): seq[tuple[d: int, k: string]] =
  ## Return ``seq[(dist, key)]`` for all trie keys with Levenshtein dist from
  ## ``key`` <= `dmax`.
  var k = newString(t.depth)
  var row = newSeq[int](key.len + 1)            #Populate first row
  for j in 0 .. key.len: row[j] = j
  for h, ch in t.root.kidc:                     #Search kids
    k[0] = ch
    result.nearLevR(t.root.kidp[h], ch, k, key, row, 1, dmax, limit)

proc collect*[T](n: Node[T], key: var string, d=0, pfx="", i=0): seq[tuple[k: string, n: Node[T]]] =
  if n == nil:
    return
  if n.term:
    result.add (k: (if i > 0: pfx[0..<i] & key else: key), n: n)
  for h, ch in n.kidc:
    key.setLen d + 1
    key[d] = ch
    result.add collect(n.kidp[h], key, d + 1, pfx, i)

proc leaves[T](r: Node[T], depth=99, pfx="", i=0, d=0):
       seq[tuple[k: string, n: Node[T]]] =
  var key = ""                  #Would be nicer to do iterator w/state bounded
  collect(r, key, d, pfx, i)    #..by depth, but seemed tricky & unimportant.

proc len*[T](t: Trie[T]): int {.inline.} =
  if t.root == nil: 0 else: t.root.cnt.int

proc contains*[T](t: Trie[T], key: string): bool {.inline.} =
  rawGet(t, key) != nil

template get[T](t: Trie[T], key: string): T =
  let n = rawGet(t, key)
  if n == nil:
    raise newException(KeyError, "key not found: " & $key)
  n.val

proc `[]`*[T](t: Trie[T], key: string): T {.inline.} =
  ## Retrieves value at ``t[key]`` or raises ``KeyError`` if missing.
  get(t, key)

proc `[]`*[T](t: var Trie[T], key: string): var T {.inline.} =
  ## Retrieves modifiable value at ``t[key]`` or raises ``KeyError`` if missing.
  get(t, key)

proc mgetOrPut*[T](t: var Trie[T], key: string, val: T): var T =
  ## Retrieves modifiable value at ``t[key]`` or inserts if missing.
  let oldLen = t.len
  var n = rawInsert(t, key)
  when T isnot void:
    n.val = val
    n.val

proc containsOrIncl*[T](t: var Trie[T], key: string, val: T): bool =
  ## Returns true iff ``t`` contains ``key`` or does ``t[key]=val`` if missing.
  let oldLen = t.len
  var n = rawInsert(t, key)
  result = t.len == oldLen
  when T isnot void:
    if not result: n.val = val

proc containsOrIncl*[T](t: var Trie[T], key: string): bool {.discardable.}=
  ## Returns true iff ``t`` contains ``key`` or inserts into ``t`` if missing.
  let oldLen = t.len
  discard rawInsert(t, key)
  result = t.len == oldLen

proc inc*[T](t: var Trie[T], key: string, val: int = 1) =
  ## Increments ``t[key]`` by ``val`` (starting from 0 if missing).
  var n = rawInsert(t, key)
  inc n.val, val

proc incl*(t: var Trie[void], key: string) =
  ## Includes ``key`` in ``t``.
  discard rawInsert(t, key)

proc incl*[T](t: var Trie[T], key: string, val: T) =
  ## Inserts ``key`` with value ``val`` into ``t``, overwriting if present
  var n = rawInsert(t, key)
  n.val = val

proc `[]=`*[T](t: var Trie[T], key: string, val: T) =
  ## Inserts ``key``, ``val``-pair into ``t``, overwriting if present.
  var n = rawInsert(t, key)
  n.val = val

iterator keys*[T](t: Trie[T]): string =
  ## yields all keys in lexicographical order.
  for tup in t.root.leaves(t.depth): yield tup.k

iterator values*[T](t: Trie[T]): T =
  ## yields all values of `t` in the lexicographical order of the
  ## corresponding keys.
  for tup in t.root.leaves(t.depth): yield tup.n.val

iterator mvalues*[T](t: var Trie[T]): var T =
  ## yields all values of `t` in the lexicographical order of the
  ## corresponding keys. The values can be modified.
  for tup in t.root.leaves(t.depth): yield tup.n.val

iterator items*[T](t: Trie[T]): string =
  ## yields all keys in lexicographical order.
  for tup in t.root.leaves(t.depth): yield tup.k

iterator pairs*[T](t: Trie[T]): tuple[key: string, val: T] =
  ## yields all (key, value)-pairs of `t`.
  for tup in t.root.leaves(t.depth): yield (tup.k, tup.val)

iterator mpairs*[T](t: var Trie[T]): tuple[key: string, val: var T] =
  ## yields all (key, value)-pairs of `t`. The yielded values can be modified.
  for tup in t.root.leaves(t.depth): yield (tup.k, tup.val)

proc `$`*[T](t: Trie[T]): string =
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

iterator keysWithPrefix*[T](t: Trie[T], prefix: string, longest=false): string =
  ## Yields all keys starting with `prefix`.
  var i = 0
  for tup in rawPfx(t, prefix, i, longest).leaves(t.depth, prefix, i):
    yield tup.k

iterator valuesWithPrefix*[T](t: Trie[T], prefix: string, longest=false): T =
  ## Yields all values of ``t`` for keys starting with ``prefix``.
  var i = 0
  for tup in rawPfx(t, prefix, i, longest).leaves(t.depth, prefix, i):
    yield tup.n.val

iterator mvaluesWithPrefix*[T](t: var Trie[T], prefix: string,
                               longest=false): var T =
  ## Yields all values of ``t`` for keys starting with ``prefix``.  The values
  ## can be modified.
  var i = 0
  for tup in rawPfx(t, prefix, i, longest).leaves(t.depth, prefix, i):
    yield tup.n.val

iterator pairsWithPrefix*[T](t: Trie[T], prefix: string,
                             longest=false): tuple[key: string, val: T] =
  ## Yields all (key, value)-pairs of `t` starting with `prefix`.
  var i = 0
  for tup in rawPfx(t, prefix, i, longest).leaves(t.depth, prefix, i):
    yield (tup.k, tup.n.val)

iterator mpairsWithPrefix*[T](t: var Trie[T], prefix: string,
                              longest=false): tuple[key: string, val: var T] =
  ## Yields all (key, value)-pairs of `t` starting with `prefix`.
  ## The yielded values can be modified.
  var i = 0
  for tup in rawPfx(t, prefix, i, longest).leaves(t.depth, prefix, i):
    yield (tup.k, tup.n.val)
#These uses overloading rathe than plural Pats to disambiguate vs `tern` names
proc uniquePfxPat*(x: openArray[string], sep="*"): seq[string] =
  ## Return unique prefixes in ``x`` assuming non-empty-string&unique ``x[i]``.
  result.setLen x.len
  var t: Trie[void]
  for i, s in x: t.incl s
  for i, s in x: result[i] = t.uniquePfxPat(s)

proc uniqueSfxPat*(x: openArray[string], sep="*"): seq[string] =
  ## Return unique suffixes in ``x`` assuming non-empty-string&unique ``x[i]``.
  result.setLen x.len
  var revd = newSeq[string](x.len)
  var t: Trie[void]
  for i, s in x:
    revd[i] = s; revd[i].reverse; t.incl revd[i]
  for i, s in revd:
    result[i] = t.uniquePfxPat(s)
    result[i].reverse
