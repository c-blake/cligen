when (NimMajor,NimMinor,NimPatch) > (0,20,2):
  {.push warning[UnusedImport]: off.} # This is only for gcarc
import std/[posix,sets,tables,strutils,strformat,parseutils], sysUt,argcvt,gcarc,osUt

proc openat*(dirfd: cint, path: cstring, flags: cint):
       cint {.varargs, importc, header: "<unistd.h>", sideEffect.}
proc fstatat*(dirfd: cint, path: cstring, stx: var Stat, flags: cint):
       cint {.importc, header: "<unistd.h>", sideEffect.}
proc faccessat*(dirfd: cint; path: cstring; mode: cint; flags: cint):
       cint {.importc, header: "<unistd.h>", sideEffect.}
proc fchmodat*(dirfd: cint; path: cstring; mode: Mode; flags: cint):
       cint {.importc, header: "<unistd.h>", sideEffect.}
proc fchownat*(dirfd: cint; path: cstring; owner: Uid; group: Gid;
               flags: cint): cint {.importc, header: "<unistd.h>", sideEffect.}
proc futimesat*(dirfd: cint; path: cstring; times: array[2, Timeval]):
       cint {.importc, header: "<unistd.h>", sideEffect.}
proc utimensat*(dirfd: cint; path: cstring; times: array[2, Timespec];
       flags: cint): cint {.importc, header: "<unistd.h>", sideEffect.}
proc futimens*(fd: cint; times: array[2, Timespec]):
       cint {.importc, header: "<unistd.h>", sideEffect.}
proc linkat*(olddirfd: cint; oldpath: cstring; newdirfd: cint; newpath: cstring;
       flags: cint): cint {.importc, header: "<unistd.h>", sideEffect.}
proc mkdirat*(dirfd: cint; path: cstring; mode: Mode):
       cint {.importc, header: "<unistd.h>", sideEffect.}
proc mknodat*(dirfd: cint; path: cstring; mode: Mode; dev: Dev):
       cint {.importc, header: "<unistd.h>", sideEffect.}
proc symlinkat*(target: cstring; newdirfd: cint; linkpath: cstring):
       cint {.importc, header: "<unistd.h>", sideEffect.}
proc readlinkat*(dirfd: cint; path: cstring; buf: cstring; bufsiz: csize):
       clong {.importc, header: "<unistd.h>", sideEffect.}
proc unlinkat*(dirfd: cint; path: cstring; flags: cint):
       cint {.importc, header: "<unistd.h>", sideEffect.}
proc renameat*(olddirfd: cint; oldpath: cstring; newdirfd: cint;
       newpath: cstring): cint {.importc, header: "<unistd.h>", sideEffect.}

template impConst*(T: untyped, path: string, name: untyped): untyped {.dirty.} =
  var `loc name` {.header: path, importc: astToStr(name) .}: `T`
  let name* {.inject.} = `loc name`

template impCint*(path: string, name: untyped): untyped {.dirty.} =
  impConst(cint, path, name)

impCint("fcntl.h", AT_FDCWD)            ## Tell *at calls to use CWorking Direct
impCint("fcntl.h", AT_SYMLINK_NOFOLLOW) ## Do not follow symbolic links
impCint("fcntl.h", AT_REMOVEDIR)        ## Remove dir instead of unlinking file
impCint("fcntl.h", AT_SYMLINK_FOLLOW)   ## Follow symbolic links
impCint("fcntl.h", AT_EACCESS)          ## Test access perm for EID,not real ID
impConst(clong, "sys/stat.h", UTIME_NOW)  ## tv_nsec value for *utimens* => now
impConst(clong, "sys/stat.h", UTIME_OMIT) ## tv_nsec value for *utimens* => omit
when defined(linux):
  const AT_NO_AUTOMOUNT* = 0x800        ## Suppress terminal automount traversal
  const AT_EMPTY_PATH*   = 0x1000       ## Allow empty relative pathname

proc log*(f: File, s: string) {.inline.} =
  ## This does nothing if ``f`` is ``nil``, but otherwise calls ``write``.
  if f != nil: f.write s

template localAlloc*(param; typ: typedesc) {.dirty.} =
  ## One often wants to allow auxiliary data that may or may not be discovered
  ## as part of an operation to be returned optionally.  One convenient pattern
  ## for this in Nim is accepting a ``ptr T`` which can be ``nil`` when the
  ## caller does not want the auxiliary data.  Routines using this pattern
  ## define local space but only use its addr if callers provide none, as in
  ## ``var loc; let par = if par == nil: loc.addr else par``.  This template
  ## abstracts that away to simply ``localAlloc(par, parTypeLessPtr)``.
  var `param here`: typ
  let param = if param == nil: `param here`.addr else: param

proc getTime*(): Timespec =
  ##Placeholder to avoid `times` module
  discard clock_gettime(0.ClockId, result)

proc cmp*(a, b: Timespec): int =
  let s = cmp(a.tv_sec.int, b.tv_sec.int)
  if s != 0: return s
  return cmp(a.tv_nsec, b.tv_nsec)

proc `<=`*(a, b: Timespec): bool = cmp(a, b) <= 0

proc `<`*(a, b: Timespec): bool = cmp(a, b) < 0

proc `-`*(a, b: Timespec): int =
  result = (a.tv_sec.int - b.tv_sec.int) * 1_000_000_000 +
           (a.tv_nsec.int - b.tv_nsec.int)

proc `$`*(x: Timespec): string =
  let d = $x.tv_nsec.int
  result = $x.tv_sec.int & "." & repeat('0', 9 - d.len) & d
  while result[^1] == '0': result.setLen result.len - 1
  if result.endsWith('.'): result.add '0'

proc argParse*(dst: var Timespec, dfl: Timespec, a: var ArgcvtParams): bool =
  proc isDecimal(s: string): bool =
    for c in s:
      if (c < '0' or c > '9') and c != '.': return false
    return true
  var val = strip(a.val)
  var sign = 1
  if val.len > 1 and val[0] in { '-', '+' }:
    if val[0] == '-': sign = -1
    val = val[1..^1]
  if len(val) == 0 or not val.isDecimal:
    a.msg="Bad value: \"$1\" for option \"$2\"; expecting non-scinote $3\n$4" %
          [ a.val, a.key, "Timespec", a.help ]
    return false
  var parsed, point: BiggestInt
  if val.startsWith('.'): val = "0" & val
  if '.' notin val: val.add '.'
  while val[^1] == '0': val.setLen val.len - 1
  point = parseBiggestInt(val, parsed)
  dst.tv_sec = Time(parsed * sign)
  val = val[point + 1 .. (point + min(9, val.len - point - 1))]
  let digits = val.len - point + 1
  if digits > 0:
    discard parseBiggestInt(val, parsed)
    dst.tv_nsec = parsed.int
    for c in 0 ..< 9 - digits: dst.tv_nsec = dst.tv_nsec * 10
  return true

proc argHelp*(dfl: Timespec, a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys, "Timespec", $dfl ]

proc toUidSet*(strs: seq[string]): HashSet[Uid] =
  ##Just parse some ints into typed Uids
  when (NimMajor,NimMinor,NimPatch) < (0,20,0): result = initSet[Uid]()
  else: result = initHashSet[Uid]()
  for s in strs: result.incl s.parseInt.Uid

proc toGidSet*(strs: seq[string]): HashSet[Gid] =
  ##Just parse some ints into typed Gids
  when (NimMajor,NimMinor,NimPatch) < (0,20,0): result = initSet[Gid]()
  else: result = initHashSet[Gid]()
  for s in strs: result.incl s.parseInt.Gid

proc getgroups*(gids: var HashSet[Gid]) =
  ## Get all gids active for current process
  proc getgroups(a1: cint, a2: ptr UncheckedArray[Gid]): cint {.importc,
    header: "<unistd.h>".}      #posix.getgroups bounds this at 0..255, but
  let n = getgroups(0, nil)     #..much larger num.grps easily supported by
  var myGids = newSeq[Gid](n)   #..2 calls - one to see size, 2nd to populate.
  let m = getgroups(n, cast[ptr UncheckedArray[Gid]](addr(myGids[0])))
  for i in 0 ..< m:             #Could check m == n, but eh.
    gids.incl(myGids[i])
  gids.incl(getegid())          #specs say to incl effective gid manually
proc getgroups*(): HashSet[Gid] = getgroups(result)

template defineIdentities(ids,Id,Entry,getid,rewind,getident,en_id,en_nm) {.dirty.} =
  proc ids*(): Table[Id, string] =
    ##Populate Table[Id, string] with data from system account files
    when (NimMajor,NimMinor,NimPatch) < (0,20,0): result = initTable[Id, string]()
    var id: ptr Entry
    when defined(android):
      proc getid(id: Id): ptr Entry {.importc.}
      for i in 0 ..< 32768:
        if (id := getid(i)) != nil:
          result[id.en_id] = $id.en_nm
    else:
      rewind()
      while (id := getident()) != nil:
        if id.en_id notin result:             #first entry wins, not last
          result[id.en_id] = $id.en_nm
defineIdentities(users, Uid, Passwd, getpwuid,setpwent,getpwent,pw_uid,pw_name)
defineIdentities(groups, Gid, Group, getgrgid,setgrent,getgrent,gr_gid,gr_name)

template defineIds(ids,Id,Entry,getid,rewind,getident,en_id,en_nm) {.dirty.} =
  proc ids*(): Table[string, Id] =
    ##Populate Table[Id, string] with data from system account files
    when (NimMajor,NimMinor,NimPatch) < (0,20,0): result = initTable[string, Id]()
    var id: ptr Entry
    when defined(android):
      proc getid(id: Id): ptr Entry {.importc.}
      for i in 0 ..< 32768:
        if (id := getid(i)) != nil:
          let idStr = $id.en_nm
          if idStr notin result:              #first entry wins, not last
            result[idStr] = id.en_id
    else:
      rewind()
      while (id := getident()) != nil:
        let idStr = $id.en_nm
        if idStr notin result:                #first entry wins, not last
          result[idStr] = id.en_id
defineIds(userIds, Uid, Passwd, getpwuid, setpwent, getpwent, pw_uid, pw_name)
defineIds(groupIds, Gid, Group , getgrgid, setgrent, getgrent, gr_gid, gr_name)

proc readlink*(path: string, err=stderr): string =
  ##Call POSIX readlink reliably: Start with a nominal size buffer & loop while
  ##the answer may have been truncated.  (Could also pathconf(p,PC_PATH_MAX)).
  result = newStringOfCap(512)
  var nBuf = 256
  var n = nBuf
  while n == nBuf:        #readlink(2) DOES NOT NUL-term, but Nim does, BUT it
    nBuf *= 2             #..is inaccessible to user-code.  So, the below does
    result.setLen(nBuf)   #..not need the nBuf + 1 it would in C code.
    n = readlink(path, cstring(result[0].addr), nBuf)
  if n <= 0:
    err.write "readlink(\"", $path, "\"): ", strerror(errno), "\n"
    result.setLen(0)
  else:
    result.setLen(n)

proc `$`*(st: Stat): string =
  ##stdlib automatic ``$(Stat)`` broken due to pad0 junk.
  "(dev: "     & $st.st_dev     & ", " & "ino: "    & $st.st_ino    & ", " &
   "nlink: "   & $st.st_nlink   & ", " & "mode: "   & $st.st_mode   & ", " &
   "uid: "     & $st.st_uid     & ", " & "gid: "    & $st.st_gid    & ", " &
   "rdev: "    & $st.st_rdev    & ", " & "size: "   & $st.st_size   & ", " &
   "blksize: " & $st.st_blksize & ", " & "blocks: " & $st.st_blocks & ", " &
   "atim: "    & $st.st_atim    & ", " & "mtim: "   & $st.st_mtim   & ", " &
   "ctim: "    & $st.st_ctim    & ")"

proc stat2dtype*(st_mode: Mode): int8 {.inline.} =
  ##Convert S_ISDIR(st_mode) style dirent types to DT_DIR style.
  int8((int(st_mode) shr 12) and 15)    # See dirent.h:IFTODT(mode)

proc getDents*(fd: cint, st: Stat, dts: ptr seq[int8] = nil,
               inos: ptr seq[Ino] = nil, avgLen=24): seq[string] =
  ##Read open dir ``fd``. If provided, also give ``d_type`` and/or ``d_ino`` in
  ##``dts`` & ``inos`` pairing with result strings.  ALWAYS skips ".", "..".
  proc fdopendir(fd: cint): ptr DIR {.importc: "fdopendir", header: "dirent.h".}
  var dir = fdopendir(fd)
  if dir == nil: return
  defer: discard closedir(dir)
  var d: ptr DirEnt
  while (d := dir.readdir) != nil:
    if (d.d_name[0] == '.' and d.d_name[1] == '\0') or
       (d.d_name[0] == '.' and d.d_name[1] == '.' and d.d_name[2] == '\0'):
          continue
    if dts != nil: dts[].add d.d_type
    if inos != nil: inos[].add d.d_ino
    result.add $cstring(addr d.d_name)

proc ns*(t: Timespec): int =
  ## Signed ns since epoch; Signed 64bit ints => +-292 years from 1970.
  int(t.tv_sec) * 1000_000_000 + t.tv_nsec

proc fileTimeParse*(code: string): tuple[tim: char, dir: int] =
  ##Parse [+-][amcvAMCV]* into a file time order specification.  In case default
  ##increasing order is non-intuitive, this provides two ways to specify reverse
  ##order: leading '-' or upper-casing.  Such reversals compose: "-A" === "a".
  if code.len < 1:
    result.dir = +1
    result.tim = 'm'
    return
  result.dir = if code[0] == '-': -1 else: +1
  result.tim = if code[0] in { '-', '+' }: code[1] else: code[0]
  if result.tim == toUpperAscii(result.tim):
    result.dir = -result.dir
    result.tim = toLowerAscii(result.tim)

proc fileTime*(st: Stat, tim: char, dir: int): int =
  ## file time useful in sorting by [+-][amcv]time; pre-parsed code.
  case tim
  of 'a': dir * ns(st.st_atim)
  of 'm': dir * ns(st.st_mtim)
  of 'c': dir * ns(st.st_ctim)
  of 'v': dir * max(ns(st.st_mtim), ns(st.st_ctim))  #"Version" time
  else: 0

proc fileTime*(st: Stat, code: string): int =
  ## file time useful in sorting by [+-][amcv]time.
  let td = fileTimeParse(code)
  fileTime(st, td.tim, td.dir)

template makeGetTimeNs(name: untyped, field: untyped) =
  proc name*(st: Stat): int = ns(st.field)
  proc name*(path: string): int =
    var st: Stat
    result = if stat(path, st) < 0'i32: 0 else: name(st)
makeGetTimeNs(getLastAccTimeNs, st_atim)
makeGetTimeNs(getLastModTimeNs, st_mtim)
makeGetTimeNs(getCreationTimeNs, st_ctim)

let strftimeCodes* = { 'a', 'A', 'b', 'B', 'c', 'C', 'd', 'D', 'e', 'E', 'F',
  #[ Unused:   ]#      'G', 'g', 'h', 'H', 'I', 'j', 'k', 'l', 'm', 'M', 'n',
  #[ J K L N Q ]#      'O', 'p', 'P', 'r', 'R', 's', 'S', 't', 'T', 'u', 'U',
  #[ f i o q v ]#      'V', 'w', 'W', 'x', 'X', 'y', 'Y', 'z', 'Z', '+',
                       '1', '2', '3', '4', '5', '6', '7', '8', '9' }

proc strftime*(fmt: string, ts: Timespec): string =
  ##Nim wrap strftime, and translate %[1..9] => '.' & that many tv_nsec digits.
  proc ns(fmt: string): string =
    var inPct = false
    for c in fmt:
      if inPct:
        inPct = false                 #'%' can take at most a 1-char argument
        if c == '%': result.add("%%")
        elif ord(c) >= ord('1') and ord(c) <= ord('9'):
          var all9 = $ts.tv_nsec
          all9 = "0".repeat(9 - all9.len) & all9
          result.add(all9[0 .. (ord(c) - ord('0') - 1)])
        else:
          result.add('%')
          result.add(c)
      else:
        if c == '%': inPct = true
        else: result.add(c)
  if fmt.len == 0: return $ts
  var tsCpy = ts.tv_sec #WTF: const time_t should -> non-var param in localtime
  var tm = localtime(tsCpy)
  result.setLen(32) #initial guess
  while result.len < 1024: #Avoid inf.loop for eg. "%p" fmt in some locales=>0.
    let res = strftime(result.cstring, result.len, fmt.ns.cstring, tm[])
    if res == 0: result.setLen(result.len * 2)  #Try again with a bigger buffer
    else       : result.setLen(res); return

type PathId* = tuple[dev: Dev, ino: Ino]
proc pathId*(path: string): PathId =
  var st: Stat
  if stat(path, st) != -1: return (st.st_dev, st.st_ino)
  return (0.Dev, 0.Ino)

proc `==`*(a, b: PathId): bool {.inline.} = a.dev == b.dev and a.ino == b.ino
proc hash*(x: PathId): int {.inline.} = x.dev.int * x.ino.int

proc readFile*(path: string, buf: var string, st: ptr Stat=nil, perRead=4096) =
  ## Read whole file of unknown (& fstat-non-informative) size using re-usable
  ## IO buffer provided.  If ``st`` is non-nil then fill it in via ``fstat``.
  buf.setLen(0)
  var off = 0
  let fd = open(path, O_RDONLY)
  if fd == -1: return                 #likely vanished between getdents & open
  defer: discard close(fd)
  if st != nil:
    if fstat(fd, st[]) == -1: return  #early return virtually impossible
    if st[].st_size > 0:
      buf.setLen st[].st_size         #may miss actively added; (a race anyway)
      let nRead = read(fd, buf[0].addr, st[].st_size)
      if nRead == st[].st_size: return
      off = buf.len                   #fall through on a short read
  while true:
    buf.setLen(buf.len + perRead)
    let nRead = read(fd, buf[off].addr, perRead)
    if nRead == -1:
      if errno == EAGAIN or errno == EINTR:
        continue
      return
    elif nRead < perRead:
      buf.setLen(off + nRead)
      break
    off += nRead

proc nanosleep*(delay: Timespec) =
  ## Carefully sleep by amount ``delay``.
  if (delay.tv_sec.int == 0 and delay.tv_nsec.int == 0) or delay.tv_sec.int < 0:
    return
  var delay = delay
  var remain: Timespec
  var ret = 0.cint
  while (ret := nanosleep(delay, remain)) != 0 and errno == EINTR:
    swap delay, remain                  #Since EFAULT may indicate EXTREME vmem
  if ret != 0:                          #..pressure, use syscall directly below.
    discard write(2.cint, "EFAULT/EINVAL from nanosleep\n".cstring, 29)

proc nice*(pid: Pid, niceIncr: cint): int =
  ## Increment nice value/scheduling priority bias of a process/thread.
  proc setpriority(which: cint, who: cuint, prio: cint): cint {.
    importc: "setpriority", header: "<sys/resource.h>" .}
  when defined(linux):
    let mx = 19
  else:
    let mx = 20
  setpriority(0.cint, pid.uint32, max(-20, min(mx, niceIncr)).cint).int

proc statOk*(path: string; st: ptr Stat=nil, err=stderr): bool {.inline.} =
  ## ``stat path`` optionally populating ``st`` if non-nil and writing any
  ## OS error message to ``err`` if non-nil.
  localAlloc(st, Stat)
  st[].st_nlink = 0                     #<1 illegal for st_nlink.  We clear in
  if stat(path, st[]) != 0'i32:         #..case error otherwise leaves stale.
    err.log &"stat({path}): {strerror(errno)}\n"
    return false
  return true

proc lstatOk*(path: string; st: ptr Stat=nil, err=stderr): bool {.inline.} =
  ## ``lstat path`` optionally populating ``st`` if non-nil and writing any
  ## OS error message to ``err`` if non-nil.
  localAlloc(st, Stat)
  st[].st_nlink = 0                     #<1 illegal for st_nlink.  We clear in
  if lstat(path, st[]) != 0'i32:        #..case error otherwise leaves stale.
    err.log &"lstat({path}): {strerror(errno)}\n"
    return false
  return true

proc st_inode*(path: string, err=stderr): Ino =
  ## Return just the ``Stat.st_inode`` field for a path.
  var st: Stat
  if stat(path, st) == -1:
    err.write "stat(\"", $path, "\"): ", strerror(errno), "\n"
  st.st_ino

proc `//`(prefix, suffix: string): string =
  # This is like stdlib os.`/` but simpler basically just for the needs of
  # `dirEntries` and `recEntries`.
  if prefix == "./":
    if suffix == "": "."
    else: suffix
  elif prefix.endsWith('/'): prefix & suffix
  else: prefix & '/' & suffix

iterator dirEntries*(dir: string; st: ptr Stat=nil; canRec: ptr bool=nil;
                     dt: ptr int8=nil; err=stderr; follow=false;
                     relative=false): string =
  ## This iterator wraps ``readdir``, optionally filling ``st[]`` if it was
  ## necessary to read, whether an entry can be recursed upon, and the ``dirent
  ## d_type`` in ``dt[]`` (or if unavailable ``DT_UNKNOWN``).  OS error messages
  ## are sent to File ``err`` (which can be ``nil``).  Yielded paths are
  ## relative to ``dir`` iff.  ``relative`` is true.
  ##
  ## ``follow`` is for the mode where outer, recursive iterations want to chase
  ## symbolic links to dirs.  ``st[]`` is filled only if needed to compute
  ## ``canRec``.  ``lstat`` is used only if ``not follow and dt[]==DT_UNKNOWN``)
  ## else ``stat`` is used.  If ``dt[]==DT_DIR`` then only ``st_ino`` is
  ## assigned.  Callers can detect if ``st`` was filled by ``st_nlink > 0``.
  localAlloc(st, Stat)
  localAlloc(dt, int8)
  var d = opendir(dir)
  if d == nil:
    err.log &"opendir({dir}): {strerror(errno)}\n"
  else:
    defer: discard d.closedir
    while true:                         #Main loop: read,filter,classify,yield
      let de = readdir(d)
      if de == nil: break
      if (de.d_name[0]=='.' and de.d_name[1]=='\0') or (de.d_name[0]=='.' and
          de.d_name[1]=='.' and de.d_name[2]=='\0'):
        continue                        #Skip "." and ".."
      var ent = $de.d_name.addr.cstring #Make a Nim string
      var path = dir // move(ent)       #Join path down from `dir`
      dt[] = de.d_type
      st[].st_nlink = 0                 #Tell caller we did no stat/lstat
      if canRec != nil:
        canRec[] = false
        if   dt[] == DT_DIR:
          canRec[] = true
          if follow:                    #Caller must track st_dev(dir) to block
            st[].st_ino = de.d_ino      #..cross dev+descend+symLink loops.
        elif dt[] == DT_LNK:
          if follow and statOk(path, st, err) and S_ISDIR(st.st_mode):
            canRec[] = true
        elif dt[] == DT_UNKNOWN:        #Weak FSes may have DT_UNKNOWN for all
          if follow:
            if statOk(path, st, err) and S_ISDIR(st.st_mode): canRec[] = true
          else:                         #Not follow-mode: only ever need `lstat`
            if lstatOk(path, st, err) and S_ISDIR(st.st_mode): canRec[] = true
      yield (if relative: ent else: path)

iterator recEntries*(dir: string; st: ptr Stat=nil; dt: ptr int8=nil,
                     follow=false, maxDepth=0, err=stderr): string =
  ## This recursively yields all paths in the FS tree up to ``maxDepth`` levels
  ## beneath ``dir`` or without bound for ``maxDepth==0``. If ``follow`` then
  ## recursion follows symbolic links to dirs. If ``err!=nil`` then OS error
  ## messages are written there.  Unlike the stdlib ``walkDirRec``, in addition
  ## to a ``maxDepth`` limit, following here avoids infinite symLink loops.
  ## If provided pointers are non-nil then they are filled like ``dirEntries``.
  ## Example:
  ##
  ## .. code-block:: nim
  ##   var st: Stat; var sum = 0      #`du` 1st & 2nd level under "." only
  ##   for path in recEntries(".", st.addr, follow=true, recurse=2):
  ##     if st.st_nlink == 0 and not statOk(path, st): stderr.write "err\n"
  ##     sum += st_blocks * 512
  localAlloc(st, Stat)
  localAlloc(dt, int8)
  type DevIno = tuple[dev: Dev, ino: Ino]             #For directory identity
  var dev: Dev                                        #Local st_dev(sub)
  var id: DevIno                                      #Local full identity
  if statOk(dir,st,err) and S_ISDIR(st[].st_mode) or  #Ensure target is a dir
     (follow and S_ISLNK(st[].st_mode)):
    var did {.noInit.}: HashSet[DevIno]               #..and also init `did`
    if follow:                                        #..with its dev,ino.
      when (NimMajor,NimMinor,NimPatch) < (0,20,0): did = initSet[DevIno](8)
      else: did = initHashSet[DevIno](8)              #Did means "put in stack"
      did.incl (dev: st[].st_dev, ino: st[].st_ino)   #..not "iterated over dir"
    var canRecurse = false                            #->true based on `follow`
    var paths  = @[""]                                #Init recursion stacks
    var dirDev = @[ st.st_dev ]
    var depths = @[ 0 ]
    let dir = if dir.endsWith('/'): dir else: dir & '/'
    yield dir
    while paths.len > 0:
      let sub   = paths.pop()                         #sub-directory or ""
      let depth = depths.pop()
      if follow: dev = dirDev.pop()                   #Get st_dev(sub)
      let target = if depth == 0: dir // sub else: sub
      for path in dirEntries(target, st, canRecurse.addr, dt, err, follow):
        if canRecurse and (maxDepth == 0 or depth + 1 < maxDepth):
          if follow:
            let d = if int(st[].st_nlink) > 0: st[].st_dev else: dev
            id = (dev: d, ino: st[].st_ino)
            if id in did:                         #Already did stack put of this
              err.log &"Already visited symLink at \"{path}\".  Loop?\n"
              continue                            #Skip
            did.incl id                           #Register as done
            dirDev.add d                          #Put st_dev(path about to add)
          paths.add  path                         #Add path to recursion stack
          depths.add depth + 1                    #Add path to recursion stack
        yield path
  else:                                 #Yield just the root for non-recursables
    yield dir

proc recEntries*(it: iterator(): string; st: ptr Stat=nil; dt: ptr int8=nil,
                 follow=false, maxDepth=0, err=stderr): iterator(): string =
  ## Return iterator yielding ``maxDepth|follow`` recursive closure of ``it``.
  result = iterator(): string =
    for root in it():
      for e in recEntries(root, st, dt, follow, maxDepth, err): yield e

iterator paths*(roots:seq[string], maxDepth=0, follow=false, file="",delim='\n',
                err=stderr, st: ptr Stat=nil, dt: ptr int8=nil): string =
  ## iterator for maybe-following, maybe-recursive closure of the union of
  ## ``roots`` and optional ``delim``-delimited input ``file`` (stdin if "-"|if
  ## "" & stdin not a tty).  Usage is ``for p in paths(roots,...): echo p``.
  ## This allows fully general path input if used in a command pipeline like
  ## ``find .  -print0 | cmd -d\\0`` (where ``-d`` sets ``delim``).
  let it = recEntries(both(roots, fileStrings(file, delim)),
                      st, dt, follow, maxDepth, err)
  for e in it(): yield e

#These two are almost universally available although not technically "POSIX"
proc setGroups*(size: csize, list: ptr Gid): cint {. importc: "setgroups",
                                                     header: "grp.h" .}

proc initGroups*(user: cstring, group: Gid): cint {. importc: "initgroups",
                                                     header: "grp.h" .}

proc dropPrivilegeTo*(newUser, newGroup: string, err=stderr): bool =
  ## Change from super-user/root to a less privileged account taking care to
  ## also change gid and re-initialize supplementary groups to what /etc/group
  ## says.  I.e., like ``su``, but in-process. (Test this works on your system
  ## by compiling this module with ``-d:testDropPriv``.)
  var gid: Gid
  var uid: Uid
  try:
    gid = groupIds()[newGroup]
  except:
    err.write "no such group: ", newGroup, '\n'
    return false
  try:
    uid = userIds()[newUser]
  except:
    err.write "no such user: ", newUser, '\n'
    return false
  if setGroups(0, nil) != 0:          #Drop supplementary group privilege
    err.write "setgroups(0,nil): ", strerror(errno), '\n'
    return false
  if initGroups(newGroup.cstring, gid) != 0:    #Init suppl gids per /etc/group
    err.write "initgroups(): ", strerror(errno), '\n'
    return false
  if setregid(gid, gid) != 0:         #Drop group privilege
    err.write "setregid(): ", strerror(errno), '\n'
    return false
  if setreuid(uid, uid) != 0:         #Finally drop user privilege
    err.write "setreuid(): ", strerror(errno), '\n'
    return false
  return true

when defined(testDropPriv):
  if dropPrivilegeTo("man", "man"):
    let arg0 = "id"
    let argv = allocCStringArray(@[ arg0 ])
    discard execvp(arg0.cstring, argv)
    stderr.write "cannot exec `id`\n"
  quit(1)

proc system*(csa: cstringArray; wait=true): cint =
  ## Like system(3) but does fork & exec of an already set up ``cstringArray``.
  ## If wait==true, returns status for WEXITSTATUS(); else returns kid pid.
  var status: cint
  case (let pid = fork(); pid):
  of -1: return cint(-1)                          # fork fails
  of 0: discard execvp(csa[0], csa); quit(1)      # kid exec err
  else:
    if wait:
      discard wait4(pid, status.addr, 0, nil)     # errs impossible in context
      return status
    else:
      return cint(pid)

proc reapAnyKids*(signo: cint) {.noconv.} =
  ## Wait on any/only waitable kids; Useful to ``signal(SIGCHLD, reapAnyKids)``
  ## to avoid zombies when treating all background children the same is ok.
  var status: cint
  while wait4(Pid(-1), status.addr, WNOHANG, nil) > 0: discard
