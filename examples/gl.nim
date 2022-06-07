import std/strutils, cligen/[osUt, procpool, mfile, mslice], cligen
proc strstr(hay, needle: cstring): cstring {.header: "string.h".}
proc memmem(h:cstring, nH:int, s:cstring, nS:int): cstring {.header:"string.h".}
proc memchr(s:cstring, c: char, nS:int): cstring {.header:"string.h".}

proc inFile(sub, path: string, mmAlways: bool): bool =
  if (let f = mopen(path); f.mem != nil):
    if sub.len == 1: result = memchr(cast[cstring](f.mem), sub[0], f.len) != nil
    elif (f.len and 4095) != 0 and not mmAlways:  # strstr seems a bit faster
      if strstr(cast[cstring](f.mem), sub.cstring) != nil: return true
    elif memmem(cast[cstring](f.mem), f.len, sub.cstring, sub.len) != nil:
      return true             # *BUT* need memmem for exact f.len mod 4096 == 0
    f.close

proc gl(jobs=0, eor='\n', mmAlways=false, sub: string, paths: seq[string]) =
  ## print each path (& `eor`) containing string `sub` with parallelism `jobs`.
  var pp = initProcPool((proc(r, w: cint) =
    var ix: uint32                # Reply w/same path index only if `sub` found
    let o = open(w, fmWrite)
    let i = open(r)
    while i.uRd(ix):
      if sub.inFile(paths[ix.int], mmAlways): discard o.uWr(ix)),
    framesOb, jobs, aux=uint32.sizeof)
  proc prn(s: MSlice) = echo paths[int(cast[ptr uint32](s.mem)[])]
  pp.evalOb 0u32 ..< paths.len.uint32, prn   # Send `paths`, print replies

when isMainModule: dispatch(gl)
