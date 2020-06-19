## This is file tree walker module with optimized getdirents functionalities.
## It also exposes all costly byproduct data like ``Statx`` buffers and ``dfd``
## to client code to use other ``\*at()`` APIs as desired.
##
## Past y2k, ``d_type``-triggered ``open(O_DIRECTORY)`` rarely fails.  Even on
## old FSes, failed ``open`` is as fast as ``lstat`` (the only way to avoid
## failure).  So, optimistic ``open`` is best *unless* you also need ``lstat``
## data for *other* reasons, in which case ``lstat``+selective-``open`` is less
## work.  This module gives both.  Client code can check ``lst.stx_nlink != 0``
## to see if further ``stat`` is needed and request ``lstat``+selective-``open``
## via the ``lstats`` parameter.  (Note: Linux grew ``O_DIRECTORY`` in 1998.)
##
## On Linux, raw ``getdents64`` usage saves 1 ``fstat`` (by either ``opendir``
## or ``fdopendir``) per dir.  BSD/AIX/.. likely allow similar.  In follow sym-
## link mode, loop blocking always needs (dev,ino) per dir, though. An opendir-
## to-stat race is easily avoided with ``fdopendir`` (maybe not on Win?).
## This packaged recursion is also careful to use the POSIX.2008 ``openat`` API
## & its sibling ``fstatat`` which largely eliminates the need to deal with full
## paths instead of just dirent filenames.

import os, sets, posix, cligen/[osUt, posixUt, statx]
export perror, st_dev, Dev

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
      when defined(dentsLocalFS):     # Sadly, this fails on sshfs/NFS/etc.
        if dp.nRd > 0 and dp.nRd + 256 + DirEnt.sizeof < dp.buf.sizeof:
          return nil                  # short read => done
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
when not declared(O_CLOEXEC):
  const O_CLOEXEC* = cint(524288)

template recFailDefault*(context: string) =
  case errno
  of ENOTDIR, EXDEV: discard        # Expected if stats==false/user req no xdev
  of EMFILE, ENFILE: discard        # Too many open files; bottom out recursion
  of 0: discard                     # Success
  else:
    let m = context & ": \"" & path & "\""; perror cstring(m), m.len
    errno = 0                       # reset after a warning has posted

template forPath*(root: string; maxDepth: int; lstats, follow, xdev: bool;
                  depth, path, dfd, nmAt, ino, dt, lst, dst, did: untyped;
                  always, preRec, postRec, recFail: untyped) =
  ## Client code sees ``depth``, ``path``, ``dfd``, ``nmAt``, ``ino``, ``dt``,
  ## maybe ``lst`` in the ``always`` branch.  ``depth`` is the recursion depth,
  ## ``path`` the full path name (rooted at ``root`` which may be CWD/something
  ## instad of ``"/"``, ``path[nmAt..^1]`` is the base name of the dirent while
  ## ``dfd`` is an open file descriptor on the directory containing it (for e.g.
  ## ``fchownat`` like APIs.  ``ino``, ``dt``, ``lst``, ``dst`` are filesystem
  ## metadata for the path name and most recent directory.
  var path = newStringOfCap(16384)
  var ino: uint64
  var dt: int8
  var dst, lst: Statx
  var dev = 0.Dev
  var did = initHashSet[tuple[dev: Dev, ino: uint64]]()

  proc maybeOpenDir(dfd: cint; path: string; nmAt: int, canRec: var bool): cint=
    let fd = openat(dfd, path[nmAt].unsafeAddr.cstring,
                    O_RDONLY or O_CLOEXEC or O_DIRECTORY)
    if fd == -1:
      return cint(-1)
    if follow or xdev:                  # Need directory identity
      if dst.stx_nlink == 0 and fstat(fd, dst) != 0:
        return fd                       # Impossible but for NFS gotchas
      dst.stx_nlink = 0                 # Mark Stat invalid
    if follow and did.containsOrIncl((dst.st_dev, dst.stx_ino)):
      stderr.write "symlink loop at: \"", path, "\"\n"
      return fd
    if xdev and dst.st_dev != dev:
      errno = EXDEV
      return fd
    canRec = true
    return fd

  proc recDent(dfd: cint, dirp: ptr DIR, nPath=0, depth=0) =
    let endsInSlash = path.len > 0 and path[^1] == '/'
    if not endsInSlash: path.add '/'
    let nmAt {.used.} = if endsInSlash: nPath else: nPath + 1
    while true:
      let d = dirp.readdir
      if d == nil: break
      if d.d_name.dotOrDotDot: continue
      ino = uint64(d.d_ino)
      let m = int(strlen(d.d_name))               # Add d_name to running path
      path.setLen nmAt + m
      copyMem path[nmAt].addr, d.d_name[0].addr, m + 1
      let mayRec = maxDepth == 0 or depth + 1 < maxDepth
      lst.stx_nlink = 0                           # Mark Stat invalid
      if mayRec and (lstats or d.d_type == DT_UNKNOWN) and
         lstatxat(dfd, d.d_name[0].addr.cstring, lst, 0.cint) == 0:
        d.d_type = stat2dtype(lst.stx_mode)       # Get d_type from Statx
      dt = d.d_type
      always      # CLIENT CODE GETS: depth,path,dfd,nmAt,ino,dt,lst,dst,did
      if mayRec and (dt in {DT_UNKNOWN, DT_DIR} or (follow and dt == DT_LNK)):
        if dt == DT_DIR: dst = lst                # Need not re-fstat for ident
        var canRec = false
        let dfd = maybeOpenDir(dfd, path, nmAt, canRec)
        if canRec:
          preRec  # ANY PRE-RECURSIVE SETUP
          let (nmAt0, len0) = (nmAt, path.len)
          let dirp = fdopendir(dfd)
          recDent(dfd, dirp, nmAt + m, depth + 1)
          path.setLen len0
          let nmAt {.used.} = nmAt0
          postRec # ONLY `path` IS NON-CLOBBERED HERE
          discard dirp.closedir
        else:
          if dfd != -1: discard close(dfd)
          recFail # CLIENT CODE SAYS HOW TO REPORT ERRORS

  let m = root.len
  path.setLen m
  copyMem path[0].addr, root[0].unsafeAddr, m + 1
  lst.stx_nlink = 0
  dst.stx_nlink = 0

  if lstat(root, lst) != 0: # lstat => user can use trailing /. to force follow
    let m = "stat: \"" & root & "\""; perror cstring(m), m.len
  let depth {.used.} = 0             # Establish other locals to visit a root
  let dfd  {.used.}  = AT_FDCWD
  let nmAt {.used.}  = 0
  ino = lst.stx_ino
  dt  = stat2dtype(lst.stx_mode)
  always      # VISIT ROOT
  if S_ISDIR(lst.stx_mode):
    dev = lst.st_dev
    var canRec = false
    let dfd = maybeOpenDir(AT_FDCWD, path, 0, canRec)
    if canRec:
      preRec  # ANY PRE-RECURSIVE SETUP
      let (nmAt0, len0) = (nmAt, path.len)
      let dirp = fdopendir(dfd)
      recDent(dfd, dirp, m)
      path.setLen len0
      let nmAt {.used.} = nmAt0
      postRec # ONLY `path` IS NON-CLOBBERED HERE
      discard dirp.closedir
    else:
      if dfd != -1: discard close(dfd)
      recFail # CLIENT CODE SAYS HOW TO REPORT ERRORS
  else:
    recFail   # CLIENT CODE SAYS HOW TO REPORT ERRORS

template forPath*(root: string; maxDepth: int; lstats, follow, xdev: bool;
                  depth, path, dfd, nmAt, ino, dt, lst, dst, did: untyped;
                  always, preRec, postRec: untyped) =
  forPath(root, maxDepth, lstats, follow, xdev,
          depth, path, dfd, nmAt, ino, dt, lst, dst, did):
    always
  do: preRec
  do: postRec
  do: recFailDefault("")

template forPath*(root: string; maxDepth: int; lstats, follow, xdev: bool;
                  depth, path, dfd, nmAt, ino, dt, lst, dst, did: untyped;
                  always, preRec: untyped) =
  forPath(root, maxDepth, lstats, follow, xdev,
          depth, path, dfd, nmAt, ino, dt, lst, dst, did):
    always
  do: preRec
  do: discard
  do: recFailDefault("")

template forPath*(root: string; maxDepth: int; lstats, follow, xdev: bool;
                  depth, path, dfd, nmAt, ino, dt, lst, dst, did: untyped;
                  always: untyped) =
  forPath(root, maxDepth, lstats, follow, xdev,
          depth, path, dfd, nmAt, ino, dt, lst, dst, did):
    always
  do: discard
  do: discard
  do: recFailDefault("")

proc find*(roots: seq[string], recurse=0, stats=false,chase=false,xdev=false,
           zero=false) =
  ## 2.75-4.5X faster than GNU "find /usr|.."; 1.7x faster than FreeBSD find
  let term = if zero: '\0' else: '\n'
  for root in (if roots.len > 0: roots else: @[ "." ]):
    forPath(root, recurse, stats, chase, xdev,
            depth, path, dfd, nmAt, ino, dt, lst, dst, did):
      path.add term; stdout.urite path; path.setLen path.len-1 #faster path,term

proc dstats*(roots: seq[string], recurse=0, stats=false,chase=false,xdev=false)=
  ## Print file depth statistics
  var histo = newSeq[int](128)
  var nF = 0                                        # number of files/dents
  var nD = 0                                        # number of dirs/recursions
  for root in (if roots.len > 0: roots else: @[ "." ]):
    forPath(root, recurse, stats, chase, xdev,
            depth, path, dfd, nmAt, ino, dt, lst, dst, did):
      histo[min(depth, histo.len - 1)].inc; nF.inc  # Deepest bin catches deeper
    do: discard                                     # No pre-recurse
    do: nD.inc                                      # Count successful recurs
    do: recFailDefault("dstats")
  echo "#Depth Nentry"
  for i, cnt in histo:
    if cnt != 0: echo i, " ", cnt
  echo "#", nF, " entries; ", nD, " okRecurs"

proc wstats*(roots: seq[string]) =
  ## stdlib ``walkDirRec`` impl of hierarchy-unaware part of ``dstats -s``
  var nF = 0
  for root in roots:
    for path in walkDirRec(root, { pcFile, pcLinkToFile, pcDir, pcLinkToDir }):
      nF.inc
  echo "#", nF, " entries"

proc showNames*(label: string, dir: seq[string], wrote: var bool) {.inline.} =
  if wrote: stdout.urite "\n"
  if label.len > 0: stdout.urite label, ":\n"
  for e in dir: stdout.urite e, "\n"
  wrote = true

proc ls1AU*(roots: seq[string], recurse=1, stats=false,chase=false,xdev=false) =
  ## -r0 is 1.7-2.25x faster than GNU "ls -1AUR --color=none /usr >/dev/null".
  var top: seq[string]
  var wrote = false
  for root in (if roots.len > 0: roots else: @[ "." ]):
    var dirs: seq[seq[string]]
    var labs: seq[string]
    dirs.add @[]
    labs.add root
    forPath(root, recurse, stats, chase, xdev,
            depth, path, dfd, nmAt, ino, dt, lst, dst, did):
      dirs[^1].add path[nmAt..^1]             # Always add name
    do:
      dirs.add @[]                            # Pre-recurse: add empty seq
      labs.add path
    do:
      let lab = labs.pop
      let label = if roots.len <= 1 and recurse == 1: "" else: lab
      showNames(label, dirs.pop, wrote)       # Post-recurse: pop last seq
    do:
      if depth == 0: top.add path             # Cannot rec at top level
      else:
        case errno
        of EXDEV, EMFILE, ENFILE: discard
        else: (let m = "ls1AU: \"" & path & "\""; perror cstring(m), m.len)
  if top.len > 0: showNames("", top, wrote)   # Show roots

type DEnt = tuple[nm: string, lst: Statx]

proc initDEnt*(path: string; nmAt: int; lst: Statx): DEnt {.inline.} =
  result.nm = path[nmAt..^1]
  if lst.stx_nlink != 0:
    result.lst = lst
  elif lstat(path, result.lst) != 0:
    let m = "lstat: \"" & path & "\""; perror cstring(m), m.len

proc showLong*(label: string, dir: seq[DEnt], wrote: var bool) {.inline.} =
  if wrote: stdout.urite "\n"
  if label.len > 0: stdout.urite label.dirName, ":\n"
  var tot = 0'u64
  for e in dir: tot += e.lst.stx_blocks
  echo "total ", tot shr 1
  for e in dir: stdout.urite e.lst.stx_blocks shr 1, " ", e.nm, "\n"
  wrote = true

proc lss1AU*(roots: seq[string], recurse=1, chase=false, xdev=false) =
  ## -r0 is 1.45-2.0x faster than "ls -s1AUR --color=none /usr >/dev/null".
  var top: seq[DEnt]
  var wrote = false
  for root in (if roots.len > 0: roots else: @[ "." ]):
    var dirs: seq[seq[DEnt]]
    var labs: seq[string]
    dirs.add @[]
    labs.add root
    forPath(root, recurse, true, chase, xdev,
            depth, path, dfd, nmAt, ino, dt, lst, dst, did):
      dirs[^1].add initDEnt(path, nmAt, lst)        # Always add name
    do:
      dirs.add @[]                                # Pre-recurse: add empty seq
      labs.add path
    do: #XXX non-gc-arc bug w/pop @Nim:ea761419ad10c440bb8f0bd29dffa4116edca5f6
      let lab = labs.pop
      let label = if roots.len <= 1 and recurse == 1: "" else: lab
      showLong(label, dirs.pop, wrote)              # Post-recurse: pop last seq
    do:
      if depth == 0: top.add initDEnt(path, 0, lst) # Cannot rec at top level
      else:
        case errno
        of EXDEV, EMFILE, ENFILE: discard
        else: (let m = "lss1AU: \"" & path & "\""; perror cstring(m), m.len)
  if top.len > 0: showLong("", top, wrote)          # Show roots

when isMainModule:
  import cligen; dispatchMulti([dents.find],[dstats],[wstats],[ls1AU],[lss1AU])
