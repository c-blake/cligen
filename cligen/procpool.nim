## This module provides a facility like Python's multiprocessing module but is
## less automagic (and also very little error handling is done) right now.
## Multiple replies from worker processes are delimited by NUL ('\0') bytes { it
## would be easy to pass an arbitrary closure iterator frameReplies that could
## work on (length, binary data) that maybe just defaulted to NUL-delimited }.
## ``MSlice`` is used as a reply type to avoid copies in case replies are large.
## Implicit right now that is replies are <= buf.sizeof.  ``examples/only.nim``
## has a complete usage example.  The 4 for loops there could be lifted into a
## template & some auto-marshal/unmarshal used to mimick Python's ``for x in
## p.imap_unordered``.  This also needs Windows portability work.  It's very
## much at the proof of concept stage.  PRs welcome to build out functionality.

import cpuinfo, posix, ./mslice
type
  Filter =  # Abstract a coprocess filter which reads|writes its stdin|stdout.
    tuple[pid: Pid; fd0, fd1: cint; off: int; buf: array[16384, char]]

  ProcPool* = object  ## A process pool to do work on multiple cores
    nProc: int
    kids: seq[Filter]
    fdset: TFdSet
    fdMax: cint

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

proc len*(pp: ProcPool): int {.inline.} = pp.nProc

proc initProcPool*(work: proc(); jobs=0): ProcPool =
  result.nProc = if jobs == 0: countProcessors() else: jobs
  result.kids.setLen result.nProc
  FD_ZERO result.fdset
  for i in 0 ..< result.nProc:                  # Create nProc Filter kids
    result.kids[i] = initFilter(work)
    FD_SET result.kids[i].fd1, result.fdset
    result.fdMax = max(result.fdMax, result.kids[i].fd1)
  result.fdMax.inc

iterator frameReplies(f: var Filter, done: var bool): MSlice =
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

proc request*(pp: ProcPool, kid: int, buf: pointer, len: int) =
  discard pp.kids[kid].fd0.write(buf, len)

proc close*(pp: ProcPool, kid: int) =
  discard pp.kids[kid].fd0.close

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
