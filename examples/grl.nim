import std/strutils, cligen/[osUt, procpool, mfile, mslice], cligen
proc strstr(hay, needle: cstring): cstring {.header: "string.h".}
proc memmem(h:cstring, nH:int, s:cstring, nS:int): cstring {.header:"string.h".}

proc inFile(sub, path: string, mmAlways: bool): bool =
  if (let f = mopen(path); f.mem != nil):
    if (f.len and 4095) != 0 and not mmAlways:  # strstr seems a bit faster
      if strstr(cast[cstring](f.mem), sub.cstring) != nil: return true
    elif memmem(cast[cstring](f.mem), f.len, sub.cstring, sub.len) != nil:
      return true             # *BUT* need memmem for exact f.len mod 4096 == 0
    f.close

proc print(eor: char, s: MSlice) {.inline.} =
  discard stdout.uriteBuffer(s.mem, s.len)
  discard stdout.uriteBuffer(eor.unsafeAddr, 1)

proc grl(jobs=0, eor='\n', mmAlways=false, sub: string, paths: seq[string]) =
  ## print each path (& `eor`) containing string `sub` with parallelism `jobs`.
  var pp = initProcPool((proc() =
    for path in getLenPfx[int](stdin):
      var n = path.len            # Reply w/same path only if `sub` is found
      if sub.inFile(path, mmAlways):
        discard stdout.uriteBuffer(cast[cstring](n.addr), n.sizeof)
        stdout.urite path),
    framesLenPfx, jobs)
  pp.evalLenPfx paths, eor.print  # Feed the pool `paths` & print any results

when isMainModule: dispatch(grl)