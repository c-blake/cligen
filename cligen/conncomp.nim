import tables

proc root(up: var seq[int], x: int): int {.inline.} =
  result = x                            # Find root defined by parent == self
  while up[result] != result:
    result = up[result]
  var x = x                             # Compress path afterwards
  while up[x] != result:                #..by doing up[all x in path] <- result
    let up0 = up[x]; up[x] = result; x = up0

proc join(up, sz: var seq[int], x, y: int) {.inline.} =
  let x = up.root(x)                    # Join/union by size
  let y = up.root(y)
  if x == y: return                     # x & y are already joined
  if sz[x] < sz[y]:                     # Attach smaller tree..
    up[x] = y                           #..to root of larger
    sz[y] += sz[x]                      # and update size of larger
  else:                                 # Mirror case of above
    up[y] = x
    sz[x] += sz[y]

iterator components*(arcs: openArray[tuple[x, y: int]], nV: int): seq[int] =
  ## yields connected components given arcs and number of unique vertices
  var up = newSeq[int](nV)              # vtxId -> parent id
  for i in 0 ..< nV: up[i] = i          # initial parents all self
  var sz = newSeq[int](nV)              # vtxId -> sz
  for i in 0 ..< nV: sz[i] = 1          # initial sizes all 1
  for arc in arcs:                      # Incorp arcs via union-find/join-root
    join up, sz, arc.x, arc.y           #  Post loop up.root(i)==component label
  var cs = initTable[int, seq[int]](nV) # component id -> all members
  for i in 0 ..< nV:                    # for each unique vertex:
    cs.mgetOrPut(up.root(i), @[]).add i #   update root[id] => members map
  for c in cs.values: yield c           # Then yield blocks of components

proc vtxId*[T](vi: var Table[T, int]; vn: var seq[T]; vo: T): int {.inline.} =
  ## Return a vertex id for maybe-already-seen obj `vo`, updating `vi` & `vn`.
  try   : result = vi[vo]                             # Already known => done
  except: result = vn.len; vi[vo] = result; vn.add vo # Put into nm->id & id->nm

when isMainModule:
  import cligen

  proc conncomp(idelim='\t', odelim="\t") =
    ## Print connected components of the graph of arcs/edges on stdin.
    var vi = initTable[string,int](999) # vertex name -> int id number
    var vn = newSeqOfCap[string](4096)  # vertex int id -> name
    var arcs = newSeqOfCap[tuple[x, y: int]](4096)
    for ln in lines(stdin):             # Parse input, assign vertex ids,
      let cs = ln.split(idelim)         #..and load up `arcs`.
      arcs.add (vtxId(vi, vn, cs[0]), vtxId(vi, vn, cs[1]))
    for c in components(arcs, vn.len):  # Emit output
      for i, e in c: stdout.write vn[e], if i < c.len - 1: odelim else: ""
      stdout.write "\n"

  dispatch(conncomp, help = { "idelim": "arc delimiter",
                              "odelim": "in-cluster delimiter" })
