import std/strutils, cligen/[osUt, procpool, mfile, mslice], cligen
proc strstr(hay, needle: cstring): cstring {.header: "string.h".}
proc memmem(h:cstring, nH:int, s:cstring, nS:int): cstring {.header:"string.h".}

var gSub: string

proc inFile() = # Reply with same path as input if gSub is in the file
  for path in getLenPfx[int](stdin):
    var n = path.len
    template wr =
      discard stdout.uriteBuffer(cast[cstring](n.addr), n.sizeof)
      stdout.urite path
    if (var f = mopen(path); f.mem != nil):
      if (f.len and 4095) == 0:
        if memmem(cast[cstring](f.mem), f.len, gSub, gSub.len) != nil: wr()
      elif strstr(cast[cstring](f.mem), gSub) != nil: wr()
      f.close

proc print(eor: char, s: MSlice) {.inline.} =
  discard stdout.uriteBuffer(s.mem, s.len)
  discard stdout.uriteBuffer(eor.unsafeAddr, 1)

proc grl(jobs=0, eor='\n', sub: string, paths: seq[string]) =
  gSub = sub
  var pp = initProcPool(inFile, framesLenPfx, jobs) # Start&drive kid pool
  pp.evalp(paths, eor.print)

when isMainModule: dispatch(grl)