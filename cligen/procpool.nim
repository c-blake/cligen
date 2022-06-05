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
## & replies are done.  The core of this is under 80 lines of code.  This set up
## is least awkward when inputs & outputs are both small and there is an easy
## message protocol, as with the example programs.
##
## Concretely this snippet computes line lengths and binary->ASCII said lengths
## in 4 parallel kids,
##
## .. code-block:: nim
##  proc paraLens(strings: openArray[string]) =
##    proc work = (for s in stdin.lines: echo s.len)
##    proc prn(s: MSlice) = echo s
##    var pp = initProcPool(work, framesLines, jobs=4)
##    pp.evalLines strings, prn
##
## Instead of `*Lines`, you likely want to use `*0term` like `examples/only.nim`
## or more generally `*LenPfx` like `examples/grl.nim`.  Interleaved output is
## not a problem since reply processing (`prn` above) is all in the parent.
## There is no need for locking unless `work` sets up & uses shared resources.
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

import std/[cpuinfo, posix, random], cligen/[mslice, sysUt, osUt]
type
  Filter* = object ## Abstract coprocess filter reading|writing its stdin|stdout
    pid: Pid        # parent uses this to control => hidden
    fd0, fd1*: cint ## request|input & reply|output file descriptors/handles
    buf*: string    ## current read buffer
    done*: bool     ## flag indicating completion
    aux*: int       ## general purpose int-sized client data, e.g. obsz

  Frames* = proc(f: var Filter): iterator(): MSlice

  ProcPool* = object  ## A process pool to do work on multiple cores
    kids: seq[Filter]
    fdsetR, fdsetW: TFdSet
    fdMaxR, fdMaxW: cint
    toR, toW: Timeval
    frames: Frames

proc len*(pp: ProcPool): int {.inline.} = pp.kids.len

proc close*(pp: ProcPool, kid: int) = discard pp.kids[kid].fd0.close

proc initFilter(work: proc(), aux: int): Filter {.inline.} =
  result.aux = aux
  var fds0, fds1: array[2, cint]
  discard fds0.pipe         # pipe for data flowing from parent -> kid
  discard fds1.pipe         # pipe for data flowing from kid -> parent
  case (let pid = fork(); pid):
  of -1: result.pid = -1    #NOTE: A when(Windows) PR with CreatePipe,
  of 0:                     #      CreateProcess is very welcome.
    discard dup2(fds0[0], 0)
    discard dup2(fds1[1], 1)
    discard close(fds0[0])
    discard close(fds0[1])
    discard close(fds1[0])
    discard close(fds1[1])
    work()
    quit(0)
  else:
    result.buf = newString(8192) # allocate, setLen, but no-init
    result.pid = pid
    result.fd0 = fds0[1]    # Parent writes to fd0 & reads from fd1;  Those are
    result.fd1 = fds1[0]    #..like the fd nums in the kid, but with RW/swapped.
    discard fcntl(result.fd0, F_SETFL, O_NONBLOCK)
    discard close(fds0[0])
    discard close(fds1[1])

proc ctrlC() {.noconv.} = quit 130
const to0 = Timeval(tv_sec: Time(0), tv_usec: 0.clong)
proc initProcPool*(work: proc(); frames: Frames; jobs=0; aux=0,
                   toR=to0, toW=to0, raiseCtrlC=false): ProcPool {.noinit.} =
  if not raiseCtrlC: setControlCHook ctrlC
  result.kids.setLen (if jobs == 0: countProcessors() else: jobs)
  FD_ZERO result.fdsetW; FD_ZERO result.fdsetR        # ABI=>No rely on Nim init
  for i in 0 ..< result.len:                          # Create Filter kids
    result.kids[i] = initFilter(work, aux)
    if result.kids[i].pid == -1:                      # -1 => fork failed
      for j in 0 ..< i:                               # for prior launched kids:
        discard result.kids[j].fd1.close              #   close fd to kid
        discard kill(result.kids[j].pid, SIGKILL)     #   and kill it.
        raise newException(OSError, "fork") # vague chance trying again may work
    FD_SET result.kids[i].fd0, result.fdsetW
    FD_SET result.kids[i].fd1, result.fdsetR
    result.fdMaxW = max(result.fdMaxW, result.kids[i].fd0)
    result.fdMaxR = max(result.fdMaxR, result.kids[i].fd1)
  result.fdMaxW.inc; result.fdMaxR.inc                # select takes fdMax + 1
  result.frames = frames

iterator readyReplies*(pp: var ProcPool): MSlice =
  var to = pp.toR                                     # Block for <= 1 ms
  var fdsetR = pp.fdsetR
  if select(pp.fdMaxR, fdsetR.addr, nil, nil, to.addr) > 0:
    for i in 0 ..< pp.len:
      if FD_ISSET(pp.kids[i].fd1, fdsetR) != 0:
        for rep in toItr(pp.frames(pp.kids[i])): yield rep

iterator finalReplies*(pp: var ProcPool): MSlice =
  var st: cint
  var n = pp.len                                      # Do final answers
  var fdset0 = pp.fdsetR
  while n > 0:
    var fdset = fdset0                                # nil timeout => block
    if select(pp.fdMaxR, fdset.addr, nil, nil, nil) > 0:
      for i in 0 ..< pp.len:
        if FD_ISSET(pp.kids[i].fd1, fdset) != 0:
          for rep in toItr(pp.frames(pp.kids[i])): yield rep
          if pp.kids[i].done:                         # got EOF from kid
            FD_CLR pp.kids[i].fd1, fdset0             # Rm from fdset
            discard pp.kids[i].fd1.close              # Reclaim fd
            discard waitpid(pp.kids[i].pid, st, 0)    # Accum CPU to par;No zomb
            n.dec

proc framesOb*(f: var Filter): iterator(): MSlice =
  ## A reply frames iterator for wrk procs writing flat, binary object results.
  let f = f.addr # Seems to relate to nimWorkaround14447; Can `lent`|`sink` fix?
  result = iterator(): MSlice = # NOTE: must cp to other mem before next call.
    let obsz = f.aux
    if (let nRd = read(f.fd1, f.buf[0].addr, obsz); nRd > 0):
      yield MSlice(mem: f.buf[0].addr, len: obsz)
    else: f.done = true

proc framesLenPfx*(f: var Filter): iterator(): MSlice =
  ## A reply frames iterator for wrk procs writing [int, value] results.
  let f = f.addr # Seems to relate to nimWorkaround14447; Can `lent`|`sink` fix?
  result = iterator(): MSlice = # NOTE: must cp to other mem before next call.
    var n = 0
    if (let nHd = read(f.fd1, n.addr, n.sizeof); nHd == n.sizeof):
      f.buf.setLen n    # Below may need loop for EINTR (if not SA_RESTART)
      if (let nRd = read(f.fd1, f.buf[0].addr, n); nRd > 0):
        yield MSlice(mem: f.buf[0].addr, len: n)
      else: f.done = true
    else: f.done = true

proc frames0term*(f: var Filter): iterator(): MSlice =
  ## A reply frames iterator for workers writing '\0'-terminated results.
  let f = f.addr # Seems to relate to nimWorkaround14447; Can `lent`|`sink` fix?
  result = iterator(): MSlice =
    if (let nRd = rdRecs(f.fd1, f.buf, '\0', 8192); nRd > 0):
      for s in MSlice(mem: f.buf[0].addr, len: nRd).mSlices('\0'): yield s
    else: f.done = true

proc framesLines*(f: var Filter): iterator(): MSlice =
  ## A reply frames iterator for workers writing '\n'-terminated results.
  let f = f.addr # Seems to relate to nimWorkaround14447; Can `lent`|`sink` fix?
  result = iterator(): MSlice =
    if (let nRd = rdRecs(f.fd1, f.buf, '\n', 8192); nRd > 0):
      for s in MSlice(mem: f.buf[0].addr, len: nRd).mSlices('\n'): yield s
    else: f.done = true

template wrReq*(fds, pp, wr, rq): untyped =
  ## Internal to `wrReqs`, this evaluates to true if a request was written.
  var to = pp.toW                               # Block for <= 1 ms
  var fdsetW = pp.fdsetW
  if select(pp.fdMaxW, nil, fdsetW.addr, nil, to.addr) > 0:
    fds.setLen 0
    for i in 0 ..< pp.len:
      if FD_ISSET(pp.kids[i].fd0, fdsetW) != 0: fds.add pp.kids[i].fd0
    fds.shuffle         # Might be nice/faster to re-jigger this logic to..
    var value = false   #..use full set of fds before doing select again.
    for fd in fds:
      if wr(fd, rq) > 0: value = true; break
    value
  else: false

# Must have `rq.len` < OS pipe buffer; Pass indices, paths, etc. to ensure this.
template wrReqs(pp, reqGen, wr, onReply: untyped) =
  var fds: seq[cint]
  for rq in reqGen:
    while not wrReq(fds, pp, wr, rq):           # possible all writers block
      for rep in pp.readyReplies: onReply(rep)  # reaping answers should unblock
  for i in 0 ..< pp.len: pp.close(i)            # Send EOFs
  for rep in pp.finalReplies: onReply(rep)      # Handle final replies

proc noop*(s: MSlice) = discard ## convenience no-op for `eval*`.

template evalOb*(pp, reqGen, onReply) = wrReqs(pp, reqGen, wr, onReply)
template evalLenPfx*(pp, reqGen, onReply) = wrReqs(pp, reqGen, wrLenBuf,onReply)
template eval0term*(pp, reqGen, onReply) = wrReqs(pp, reqGen, wr0term, onReply)
template evalLines*(pp, reqGen, onReply) = wrReqs(pp, reqGen, wrLine, onReply)
proc frames0*(f: var Filter): (iterator(): MSlice) {.deprecated:
  "use `frames0term`".} = frames0term(f)
template eval*(pp, reqGen, onReply: untyped) {.deprecated: "use `eval0term`".} =
  eval0term(pp, reqGen, onReply)
template evalp*(pp, reqGen, onReply: untyped) {.deprecated:"use `evalLenPfx`".}=
  evalLenPfx(pp, reqGen, onReply)
