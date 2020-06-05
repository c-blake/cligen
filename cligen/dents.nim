## Past y2k, ``d_type``-triggered ``open(O_DIRECTORY)`` rarely fails.  Even on
## an old FS, failed-``open`` is as fast as ``lstat``, the only way to avoid
## failure.  So, optimistic-``open`` is fastest *unless* you also need ``lstat``
## data for *other* reasons, in which case ``lstat``+selective-``open`` is less
## work.  This module gives both.  Client code can check ``st.st_nlink != 0`` to
## see if further ``stat`` is needed and request ``lstat``+selective-``open``
## via the ``lstats`` parameter.  (Note: Linux only grew O_DIRECTORY in 1998.)
##
## On Linux, raw getdents64 usage saves 1 fstat (by either opendir or fdopendir)
## per dir.  BSD/AIX/.. likely allow similar move.  In follow-symlink mode, loop
## blocking always needs (dev,ino) per dir, though.  An opendir-to-stat race is
## easily avoided with fdopendir (maybe not on Win?).

import os, sets, posix, cligen/[osUt, posixUt, statx]
export perror

type csize_t = culong             # To compile with older Nim's
type DirName = array[256, cchar]  # Some helpers for names in dirents
proc strlen(s: cstring): csize_t {.importc: "strlen", header: "<string.h>".}
proc strlen(a: DirName): csize_t {.inline.} = a[0].unsafeAddr.cstring.strlen

proc dotOrDotDot*(nm: DirName): bool {.inline.} =
  nm[0] == '.' and (nm[1] == '\0' or (nm[1] == '.' and nm[2] == '\0'))

when defined(linux):
  type
    DirEnt = object
      d_ino, d_off: int64   ## 64-bit inode, offset to next
      d_reclen:     uint16  ## size of this dirent
      d_type:       int8    ## file type
      d_name:       DirName ## null-terminated filename

    DIR = object
      fd, nRd, bpos, pad: cint
      buf: array[4066, char] # 4080 total; maybe 16B allocator overhead

  proc syscall(nr: cint, a1: cint, a2: pointer, a3: csize_t): cint {.
    importc: "syscall", header: "<sys/syscall.h>", varargs .}
  var SYS_getdents64 {.header: "unistd.h", importc: "SYS_getdents64".}: cint
  proc getdents(fd: cint, buf: pointer, len: int): cint {.inline.} =
    syscall(SYS_getdents64, fd, buf, csize_t(len))

  proc fdopendir(fd: cint): ptr DIR {.inline.} =
    result = DIR.createU
    result.fd = fd
    result.nRd = 0
    result.bpos = 0

  proc closedir(dp: ptr DIR): int {.inline.} =
    result = close(dp.fd)
    dp.dealloc

  proc readdir(dp: ptr DIR): ptr DirEnt {.inline.} =
    if dp.bpos == dp.nRd:             # Used all that had been read => Read more
      dp.nRd = getdents(dp.fd, dp.buf[0].addr, dp.buf.sizeof)
      if dp.nRd == -1: stderr.write "getdents\n"; return nil # NFS/etc. gotcha
      if dp.nRd == 0: return nil      # done
      dp.bpos = 0
    result = cast[ptr DirEnt](dp.buf[dp.bpos].addr)
    dp.bpos += cint(result.d_reclen)
else:                   #XXX stdlib should add both `fdopendir` & `O_DIRECTORY`
  proc fdopendir(fd: cint): ptr DIR {.importc, header: "<dirent.h>".}
  # cimport of these sometimes fails on poorly tested non-Linux, but the numbers
  # are age-old constants.  Maybe `when compiles()` would be best?
  const EXDEV = 18; const ENOTDIR = 20; const ENFILE = 23; const EMFILE = 24
var O_DIRECTORY {.header: "fcntl.h", importc: "O_DIRECTORY".}: cint

template forPath*(root: string; recurse: int; lstats, follow, xdev: bool;
                  depth, path, nameAt, ino, dt, lst, st, recFailed: untyped;
                  openFail, always, preRec, postRec: untyped) =
  ## Client code sees new ``depth``, ``path``, ``nameAt``, ``ino``, ``dt``,
  ## maybe ``lst`` in the ``always`` branch.  ``depth`` is the recursion depth,
  ## ``path`` the full path name (rooted at ``root`` which may be CWD/something
  ## instad of ``"/"``, ``path[nameAt..^1]`` is the base name of the directory,
  ## entry, ``ino``, ``dt``, ``lst``, ``st`` are the filesystem metadata for the
  ## path name, and ``recFailed`` is a bool in the ``postRec`` clause indicating
  ## that recursion failed (most likely due either to permission problems or a
  ## race with some other deleting process).
  var path = newStringOfCap(16384)
  var ino: Ino
  var dt: int8
  var st, lst: Statx
  var did = initHashSet[tuple[dev: Dev, ino: Ino]]()

  # The optimistic open implementation
  proc recDent(nPath=0, maxDepth=0, dev=0.Dev, depth=0): bool =
    let fd = open(path, O_RDONLY or O_CLOEXEC or O_DIRECTORY)
    if fd == -1:
      openFail; return true     # CLIENT CODE SAYS HOW TO REPORT ERRORS
    let dirp = fdopendir(fd)
    if follow or xdev:          # Need directory identity
      if st.st_nlink == 0 and fstat(fd, st) != 0:
        return true             # Impossible but for NFS gotchas
      st.st_nlink = 0           # Mark Stat invalid
    if follow and did.containsOrIncl((st.st_dev, st.st_ino)):
      stderr.write "symlink loop at: \"",path,"\"\n"
      return true
    if xdev and st.st_dev != dev:
      errno = EXDEV
      return true
    path.add '/'
    let nameAt {.used.} = nPath + 1
    while true:
      let d = dirp.readdir
      if d == nil: break
      if d.d_name.dotOrDotDot: continue
      ino = Ino(d.d_ino)
      let m = int(strlen(d.d_name))               # Add d_name to running path
      path.setLen nPath + 1 + m
      copyMem path[nPath + 1].addr, d.d_name[0].addr, m + 1
      let mayRec = maxDepth == 0 or depth + 1 < maxDepth
      lst.st_nlink = 0                            # Mark Stat invalid
      if mayRec and (lstats or d.d_type==DT_UNKNOWN) and lstat(path, lst)==0:
        d.d_type = stat2dtype(lst.st_mode)        # Get d_type from Statx
      dt = d.d_type
      always    # CLIENT CODE USES: `depth`,`path`,`nameAt`,`ino`,`dt`,`lst`,`st`
      if mayRec and (dt in {DT_UNKNOWN, DT_DIR} or (follow and dt == DT_LNK)):
        if dt == DT_DIR: st = lst                 # Need not re-fstat for ident
        preRec  # ANY PRE-RECURSIVE SETUP
        let recFailed {.used.}= recDent(nPath + m + 1, maxDepth, dev, depth + 1)
        postRec # ONLY `path` IS NON-CLOBBERED HERE
    discard closedir(dirp)

  let m = root.len
  path.setLen m
  copyMem path[0].addr, root[0].unsafeAddr, m + 1
  if xdev:  # lstat means users can use (or not) trailing /. to follow or not.
    var rSt: Statx # WTF: weird EACCESS on /tmp/proc->/proc link (GNU find,too)
    if lstat(root, rSt) == 0: discard recDent(m, recurse, rSt.st_dev)
    else:
      let m = "stat: \""&root&"\""; perror cstring(m), m.len
  else: discard recDent(m, recurse)

proc find*(roots: seq[string], recurse=0, stats=false,chase=false,xdev=false,
           zero=false) =
  ## 2.5-4.5X faster than GNU "find /usr|.."; 1.5x faster than FreeBSD find
  let term = if zero: '\0' else: '\n'
  for root in (if roots.len > 0: roots else: @[ "." ]):
    forPath(root, recurse, stats, chase, xdev,
            depth, path, nameAt, ino, dt, lst, st, recFail):
      case errno
      of ENOTDIR, EXDEV: discard  # Expected if stats==false/user req no xdev
      of EMFILE, ENFILE: return   # Too many open files; bottom out recursion
      else:
        let m = "find: \""&path&"\""; perror cstring(m), m.len
    do: path.add term; stdout.urite path; path.setLen path.len-1 # stdout.urite path,term
    do: discard                   # No pre-recurse
    do: discard                   # No post-recurse

proc dstats*(roots: seq[string], recurse=0, stats=false,chase=false,xdev=false)=
  ## Print file depth statistics
  var histo = newSeq[int](128)
  var nF = 0
  var nD = 0
  for root in (if roots.len > 0: roots else: @[ "." ]):
    forPath(root, recurse, stats, chase, xdev,
            depth, path, nameAt, ino, dt, lst, st, recFail):
      case errno
      of ENOTDIR, EXDEV: discard  # Expected if stats==false/user req no xdev
      of EMFILE, ENFILE: return   # Too many open files; bottom out recursion
      else:
        let m = "dstats: \""&path&"\")"; perror cstring(m), m.len
    do: histo[min(depth, histo.len-1)].inc; nF.inc  # Deepest bin catches deeper
    do: discard                                     # No pre-recurse
    do: nD.inc int(not recFail)                     # Count successful recurs
  echo "#Depth Nentry"
  for i, cnt in histo:
    if cnt != 0: echo i, " ", cnt
  echo "#", nF, " entries; ", nD, " okRecurs"

proc wstats*(roots: seq[string]) =
  ## Just for timing comparison purposes; Same speed as ``dstats -s``.
  var nF = 0
  for root in roots:
    for path in walkDirRec(root, { pcFile, pcLinkToFile, pcDir, pcLinkToDir }):
      nF.inc
  echo "#", nF, " entries"

proc showNames*(dirNm: string, dir: seq[string], wrote: var bool) {.inline.} =
  if dir.len > 0:
    if wrote: stdout.urite "\n"
    if dirNm.len > 0: stdout.urite dirNm, ":\n"
    for e in dir:
      stdout.urite e, "\n"
    wrote = true

proc ls1AU*(roots: seq[string], recurse=1, stats=false,chase=false,xdev=false) =
  ## -r0 is 1.5-2x faster than GNU "ls -1AUR --color=none /usr >/dev/null".
  var top: seq[string]
  var wrote = false
  for root in (if roots.len > 0: roots else: @[ "." ]):
    var dirs: seq[seq[string]]
    dirs.add @[]
    forPath(root, recurse, stats, chase, xdev,
            depth, path, nameAt, ino, dt, lst, st, recFail):
      case errno
      of EXDEV: discard             # Expected if stats==false/user req no xdev
      of EMFILE, ENFILE: return     # Too many open files; bottom out recursion
      of ENOTDIR: (if depth == 0: top.add path) # Not dir at top level
      else:
        let m = "ls1AU: \""&path&"\")"; perror cstring(m), m.len
    do: dirs[^1].add path[nameAt..^1]         # Always add name
    do: dirs.add @[]                          # Pre-recurse: add empty seq
    do: showNames(path, dirs.pop, wrote)      # Post-recurse: pop last seq
    #end template call
    let label = if roots.len>1: path else: "" # Skip label on <= 1 roots
    showNames(label, dirs.pop, wrote)         # Show top of recursion
  showNames("", top, wrote)                   # Show roots

type DEnt = tuple[nm: string, lst: Statx]

proc initDEnt*(path: string; nameAt: int; lst, st: Statx): DEnt {.inline.} =
  result.nm = path[nameAt..^1]
  if lst.st_nlink != 0:
    result.lst = lst
  elif lstat(path, result.lst) != 0:
    let m = "lstat: \""&path&"\")"; perror cstring(m), m.len

proc showLong*(dirNm: string, dir: seq[DEnt], wrote: var bool) {.inline.} =
  if wrote: stdout.urite "\n"
  if dirNm.len > 0: stdout.urite dirNm, ":\n"
  var tot = 0
  for e in dir: tot += e.lst.st_blocks
  echo "total ", tot shr 1
  for e in dir:
    stdout.urite e.lst.st_blocks shr 1, " ", e.nm, "\n"
  wrote = true

proc lssAU*(roots: seq[string], recurse=1, stats=false,chase=false,xdev=false) =
  ## -r0 is 1.14-1.6x faster than "ls -sAUR --color=none /usr >/dev/null".
  var top: seq[DEnt]
  var wrote = false
  for root in (if roots.len > 0: roots else: @[ "." ]):
    var dirs: seq[seq[DEnt]]
    dirs.add @[]
    forPath(root, recurse, stats, chase, xdev,
            depth, path, nameAt, ino, dt, lst, st, recFail):
      case errno
      of EXDEV: discard             # Expected if stats==false/user req no xdev
      of EMFILE, ENFILE: return     # Too many open files; bottom out recursion
      of ENOTDIR: (if depth == 0: top.add initDEnt(path, 0, lst, st))
      else:
        let m = "lssAU: \""&path&"\")"; perror cstring(m), m.len
    do: dirs[^1].add initDEnt(path, nameAt, lst, st)      # Always add name
    do: dirs.add @[]                              # Pre-recurse: add empty seq
    do: showLong(path, dirs.pop, wrote)           # Post-recurse: pop last seq
    #end template call
    let label = if roots.len>1 or wrote: path else: "" # Skip label sometimes
    showLong(label, dirs.pop, wrote)              # Show top of recursion
  if top.len > 0: showLong("", top, wrote)        # Show roots

when isMainModule:
  import cligen; dispatchMulti([dents.find],[dstats],[wstats],[ls1AU],[lssAU])
# GNU coreutils find  use ~3x the memory, ~3.5x the syscalls, 2.5x the time:
# strace -c find /usr >/dev/null
# % time     seconds  usecs/call     calls    errors syscall
# ------ ----------- ----------- --------- --------- -----------
#  29.32    0.676760           1    501812           fcntl
#  24.42    0.563779           1    403082           close
#  16.38    0.378104           1    201366           getdents64
#  14.39    0.332283           1    201212           newfstatat
#   7.96    0.183735           1    102486         6 openat
#   6.19    0.142987           1    102480           fstat
#   1.32    0.030490           1     23203           write
#   ...
# ------ ----------- ----------- --------- --------- -----------
# 100.00    2.308406           1   1535743         9 total
# strace -c ./dents find /usr >/n
# % time     seconds  usecs/call     calls    errors syscall
# ------ ----------- ----------- --------- --------- -----------
#  49.55    0.397041           1    205489           getdents64
#  27.12    0.217287           2    100614           openat
#  19.26    0.154359           1    100614           close
#   4.07    0.032588           1     23203           write
# 100.00    0.801275           1    429997         2 total
# Investigating, GNU find is hamstrung by obscure case of hierarchy depth > open
# fd limit.  Failing informatively seems better but for `rm -rf pathology-tree`.
