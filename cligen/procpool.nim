## This module provides a facility like Python's multiprocessing module but is
## less automagic & little error handling is done.  `MSlice` is used as a reply
## type to avoid copy in case replies are large.  Auto-pack/unpack logic could
## mimic Python's `for x in p.imap_unordered` more closely.  While only at Proof
## Of Concept stage, the example `(frames|eval)(0term|LenPfx)` programs work ok.
##
## In more detail, this module abstracts the orchestration activity of a parent
## striping work over a pool of classic kid coprocesses { i.e. a double-pipe to
## each kid; How classic?  Ksh88 had `coproc`. }  Kids are the user code here &
## are basically just stdin-stdout filters needing only request-reply framing.
## The parent just loops over work generation passed in `initProcPool`, writing
## request frames to each kid, reading & framing whatever replies until the work
## & replies are done.  The core of this is under 90 lines of code.  This set up
## is least awkward when inputs & outputs are both small and there is an easy
## message protocol, as with the example programs.
##
## Many prog.lang people seem unaware that processes & threads are distinguished
## mostly by safe vs. unsafe defaults { see Linux `clone` after Plan9 `rfork` }.
## Memory can be opt-in-shared via `memfiles` & RAM files can avoid device IO &
## copying (other than short paths) to reduce differences to the awkwardness of
## pointers becoming relative to named files.  Opt-into-risk designs are always
## "more work on-purpose" for client code.  Additional benefits are bought here:
## seamless persistent data, well separated resource limits/state/etc. Procs are
## about as fast, esp. in pre-spawned pools.  YMMV, but shared-all can cost more
## than it saves.  Procs can be slower to build sharing *OR* faster from removed
## contention { e.g. if kids do memfiles IO, thread-sibs block each others' VM
## edits in fast (un)map cycles, but proc-sibs have private, uncontended VM }.
## Since one situation's "awkward" is another's "expressing vital constraints",
## good ecosystems should have libs for both (and for files as named arenas).
## This module is only a baby step in that direction that perhaps can inspire.

import std/[cpuinfo, posix], ./mslice, ./sysUt
type
  Filter* = object ## Abstract coprocess filter reading|writing its stdin|stdout
    pid: Pid
    fd0, fd1*: cint
    off*: int
    done*: bool
    buf*: string

  Frames* = proc(f: var Filter): iterator(): MSlice

  ProcPool* = object  ## A process pool to do work on multiple cores
    bufSz: int
    kids: seq[Filter]
    fdset: TFdSet
    fdMax: cint
    frames: Frames

proc len*(pp: ProcPool): int {.inline.} = pp.kids.len

proc request*(pp: ProcPool, kid: int, buf: pointer, len: int) =
  discard pp.kids[kid].fd0.write(buf, len)

proc close*(pp: ProcPool, kid: int) =
  discard pp.kids[kid].fd0.close

# NOTE: A when(Windows) PR doing CreatePipe/CreateProcess is welcome.
proc initFilter(work: proc(), bufSz: int): Filter {.inline.} =
  var fds0, fds1: array[2, cint]
  discard fds0.pipe         # pipe for data flowing from parent -> kid
  discard fds1.pipe         # pipe for data flowing from kid -> parent
  case (let pid = fork(); pid):
  of -1: result.pid = -1
  of 0:
    discard dup2(fds0[0], 0)
    discard dup2(fds1[1], 1)
    discard close(fds0[0])
    discard close(fds0[1])
    discard close(fds1[0])
    discard close(fds1[1])
    work()
    quit(0)
  else:
    result.buf = newString(bufSz) # allocate, setLen, but no-init
    result.pid = pid
    result.fd0 = fds0[1]    # Parent writes to fd0 & reads from fd1;  Those are
    result.fd1 = fds1[0]    #..like the fd nums in the kid, but with RW/swapped.
    discard close(fds0[0])
    discard close(fds1[1])

proc initProcPool*(work: proc(); frames: Frames; jobs = 0;
                   bufSize = 16384): ProcPool {.noinit.} =
  result.kids.setLen (if jobs == 0: countProcessors() else: jobs)
  FD_ZERO result.fdset
  for i in 0 ..< result.len:                          # Create Filter kids
    result.kids[i] = initFilter(work, bufSize)
    if result.kids[i].pid == -1:                      # -1 => fork failed
      for j in 0 ..< i:                               # for prior launched kids:
        discard result.kids[j].fd1.close              #   close fd to kid
        discard kill(result.kids[j].pid, SIGKILL)     #   and kill it.
        raise newException(OSError, "fork") # vague chance trying again may work
    FD_SET result.kids[i].fd1, result.fdset
    result.fdMax = max(result.fdMax, result.kids[i].fd1)
  result.fdMax.inc                                    # select takes fdMax + 1
  result.frames = frames

iterator readyReplies*(pp: var ProcPool): MSlice =
  var noTO: Timeval                                   # Zero timeout => no block
  var fdset = pp.fdset
  if select(pp.fdMax, fdset.addr, nil, nil, noTO.addr) > 0:
    for i in 0 ..< pp.len:
      if FD_ISSET(pp.kids[i].fd1, fdset) != 0:
        for rep in toItr(pp.frames(pp.kids[i])): yield rep

iterator finalReplies*(pp: var ProcPool): MSlice =
  var st: cint
  var n = pp.len                                      # Do final answers
  var fdset0 = pp.fdset
  while n > 0:
    var fdset = fdset0                                # nil timeout => block
    if select(pp.fdMax, fdset.addr, nil, nil, nil) > 0:
      for i in 0 ..< pp.len:
        if FD_ISSET(pp.kids[i].fd1, fdset) != 0:
          for rep in toItr(pp.frames(pp.kids[i])): yield rep
          if pp.kids[i].done:                         # got EOF from kid
            FD_CLR pp.kids[i].fd1, fdset0             # Rm from fdset
            discard pp.kids[i].fd1.close              # Reclaim fd
            discard waitpid(pp.kids[i].pid, st, 0)    # Accum CPU to par;No zomb
            n.dec

proc framesLenPfx*(f: var Filter): iterator(): MSlice =
  ## An output frames iterator for wrk procs writing [int, value] results.
  let f = f.addr # Seems to relate to nimWorkaround14447; Can `lent`|`sink` fix?
  result = iterator(): MSlice = # NOTE: must cp to other mem before next call.
    var n = 0
    if (let nHd = read(f.fd1, n.addr, n.sizeof); nHd == n.sizeof):
      f.buf.setLen n #XXX below needs a loop for big `n` in case of EINTR.
      if (let nRd = read(f.fd1, f.buf[0].addr, n); nRd > 0):
        yield MSlice(mem: f.buf[0].addr, len: n)
      else: f.done = true
    else: f.done = true

template evalLenPfx*(pp, reqGen, onReply: untyped) =
  ## Use `pp=initProcPool(wrk)` & this to send strings made by `reqGen` (any
  ## iterator expr) to `wrk` stdin as (P)refixed length,val pairs & pass stdout-
  ## emitted framed replies to `onReply`.  `examples/grl.nim` is a full demo.
  var i = 0; var n: int
  for req in reqGen:
    n = req.len
    discard pp.kids[i].fd0.write(n.addr, n.sizeof)
    discard pp.kids[i].fd0.write(req[0].unsafeAddr, n) # Let full pipe block
    i = (i + 1) mod pp.len
    if i + 1 == pp.len:                         # At the end of each req cycle
      for rep in pp.readyReplies: onReply(rep)  #..handle ready replies.
  for i in 0 ..< pp.len: pp.close(i)            # Send EOFs
  for rep in pp.finalReplies: onReply(rep)      # Handle final replies

proc frames0term*(f: var Filter): iterator(): MSlice =
  ## An output frames iterator for workers writing '\0'-terminated results.
  let f = f.addr # Seems to relate to nimWorkaround14447; Can `lent`|`sink` fix?
  result = iterator(): MSlice = # NOTE: results must be <= bufSz
    let nRd = read(f.fd1, f.buf[f.off].addr, f.buf.len - f.off)
    if nRd > 0:
      let ms = MSlice(mem: f.buf[0].addr, len: f.off + nRd)
      let eoms = cast[uint](ms.mem) + cast[uint](ms.len)
      f.off = 0
      for s in ms.mSlices('\0'):
        let eos = cast[uint](s.mem) + cast[uint](s.len)
        if eos < eoms and cast[ptr char](eos)[] == '\0':
          yield s
        else:
          f.off = s.len
          moveMem f.buf[0].addr, s.mem, s.len
    else:
      f.done = true

template eval0term*(pp, reqGen, onReply: untyped) =
  ## Use `pp=initProcPool(wrk)` & this to send Nim strings made by `reqGen` (any
  ## iterator expr) to `wrk` stdin as 0-terminated & pass stdout-emitted framed
  ## replies to `onReply`.  `examples/only.nim` is a full demo.
  var i = 0
  for req in reqGen:
    pp.request(i, cstring(req), req.len + 1)    # keep NUL; Let full pipe block
    i = (i + 1) mod pp.len
    if i + 1 == pp.len:                         # At the end of each req cycle
      for rep in pp.readyReplies: onReply(rep)  #..handle ready replies.
  for i in 0 ..< pp.len: pp.close(i)            # Send EOFs
  for rep in pp.finalReplies: onReply(rep)      # Handle final replies

proc noop*(s: MSlice) = discard
  ## A convenience no-op which does nothing with a `rep` for `eval0|evalp`.

proc frames0*(f: var Filter): (iterator(): MSlice) {.deprecated:
  "use `frames0term`".} = frames0term(f)
template eval*(pp, reqGen, onReply: untyped) {.deprecated: "use `eval0`".} =
  eval0term(pp, reqGen, onReply)
template evalp*(pp, reqGen, onReply: untyped) {.deprecated: "use `eval0`".} =
  evalLenPfx(pp, reqGen, onReply)
