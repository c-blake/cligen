type
  PrefetchRW* {.size: cint.sizeof.} = enum
    pfRead  = 0
    pfWrite = 1
  PrefetchKind* {.size: cint.sizeof.} = enum
    pfEvictAll  = 0
    pfEvictL1   = 1
    pfEvictL2   = 2
    pfEvictNone = 3

#XXX or defined(clang) etc. You may need some gcc flags for this to do anything.
when defined(cpuPrefetch) and defined(gcc):
  proc prefetch*(data: pointer, rw=pfRead, kind=pfEvictNone) {.
    importc: "__builtin_prefetch", nodecl .}
  proc prefetchw*(data: pointer, kind=pfEvictNone) {.inline.} =
    prefetch(data, pfWrite, kind)
else:
  proc prefetch*(data: pointer, rw=pfRead, kind=pfEvictNone) {.inline.} =discard
  proc prefetchw*(data: pointer, kind=pfEvictNone) {.inline.} = discard
