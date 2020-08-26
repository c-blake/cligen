## This module provides a facility like Python's multiprocessing module but is
## less automagic (and also very little error handling is done) right now.
## Multiple replies from worker processes are delimited by NUL ('\0') bytes.
## ``MSlice`` is used as a reply type to avoid copies in case replies are large.
## Implicit right now that is replies are <= buf.sizeof.  Auto-marshal/unmarshal
## logic might mimick Python's ``for x in p.imap_unordered`` more closely.  This
## is very much at the proof of concept stage.  PRs welcome to build it out.

import cpuinfo, posix, ./mslice
type
  Filter =  # Abstract a coprocess filter which reads|writes its stdin|stdout.
    tuple[pid: Pid; fd0, fd1: cint; off: int; buf: array[16384, char]]

  ProcPool* = object  ## A process pool to do work on multiple cores
    nProc: int
    kids: seq[Filter]
    fdset: TFdSet
    fdMax: cint

proc len*(pp: ProcPool): int {.inline.} = pp.nProc

proc request*(pp: ProcPool, kid: int, buf: pointer, len: int) =
  discard pp.kids[kid].fd0.write(buf, len)

proc close*(pp: ProcPool, kid: int) =
  discard pp.kids[kid].fd0.close

iterator frameReplies(f: var Filter, done: var bool): MSlice =
  #XXX Should probably be a parameter to readyReplies, finalReplies, and eval.
  let nRd = read(f.fd1, f.buf[f.off].addr, f.buf.sizeof - f.off)
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
    done = true

# The next 4 procs use Unix select not stdlib `selectors` for now since Windows
# CreatePipe/CreateProcess seem tricky for parent-kid coprocesses and I have no
# test platform.  If some one knows how to do that, submit a when(Windows) PR.
proc initFilter(work: proc()): Filter {.inline.} =
  var fds0, fds1: array[2, cint]
  discard fds0.pipe         # pipe for data flowing from parent -> kid
  discard fds1.pipe         # pipe for data flowing from kid -> parent
  let pid = fork()
  if pid == 0:
    discard dup2(fds0[0], 0)
    discard dup2(fds1[1], 1)
    discard close(fds0[0])
    discard close(fds0[1])
    discard close(fds1[0])
    discard close(fds1[1])
    work()
    quit(0)
  else:
    result.pid = pid
    result.fd0 = fds0[1]    # Parent writes to fd0 & reads from fd1;  Those are
    result.fd1 = fds1[0]    #..like the fd nums in the kid, but with RW/swapped.
    discard close(fds0[0])
    discard close(fds1[1])

proc initProcPool*(work: proc(); jobs=0): ProcPool =
  result.nProc = if jobs == 0: countProcessors() else: jobs
  result.kids.setLen result.nProc
  FD_ZERO result.fdset
  for i in 0 ..< result.nProc:                  # Create nProc Filter kids
    result.kids[i] = initFilter(work)
    FD_SET result.kids[i].fd1, result.fdset
    result.fdMax = max(result.fdMax, result.kids[i].fd1)
  result.fdMax.inc

iterator readyReplies*(pp: var ProcPool): MSlice =
  var done: bool
  var noTO: Timeval                                   # Zero timeout => no block
  var fdset = pp.fdset
  if select(pp.fdMax, fdset.addr, nil, nil, noTO.addr) > 0:
    for i in 0 ..< pp.nProc:
      if FD_ISSET(pp.kids[i].fd1, fdset) != 0:
        for s in pp.kids[i].frameReplies(done):
          yield s

iterator finalReplies*(pp: var ProcPool): MSlice =
  var st: cint
  var n = pp.nProc                                    # Do final answers
  var fdset0 = pp.fdset
  while n > 0:
    var fdset = fdset0                                # nil timeout => block
    if select(pp.fdMax, fdset.addr, nil, nil, nil) > 0:
      for i in 0 ..< pp.nProc:
        if FD_ISSET(pp.kids[i].fd1, fdset) != 0:
          var done = false
          for reply in pp.kids[i].frameReplies(done):
            yield reply
          if done:                                    # Worker quit
            FD_CLR pp.kids[i].fd1, fdset0             # Rm from fdset
            discard pp.kids[i].fd1.close              # Reclaim fd
            discard waitpid(pp.kids[i].pid, st, 0)    # Accum CPU to par;No zomb
            n.dec

template eval*(pp, req, rep, reqGen, onReply: untyped) =
  ## The idea is to use `pp = initProcPool()` and then use this template to give
  ## identifiers `req` and `rep`, a generator of requests (any iterator expr),
  ## and `onReply` to do something upon any reply (some expr involving `rep`).
  ## No reply at all is considered valid here; Ctrl flow options would be nice.
  ## ``examples/only.nim`` has a complete usage example.
  var i = 0
  for req in reqGen:
    pp.request(i, cstring(req), req.len + 1)    # keep NUL; Let full pipe block
    i = (i + 1) mod pp.len
    if i + 1 == pp.len:                         # At the end of each req cycle
      for rep in pp.readyReplies:               #..handle ready replies.
        onReply
  for i in 0 ..< pp.len:                        # Send EOFs
    pp.close(i)
  for rep in pp.finalReplies:                   # Handle final replies
    onReply
