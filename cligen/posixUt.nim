import os, posix, sets, tables, strutils, ./sysUt

proc getTime*(): Timespec =
  ##Placeholder to avoid `times` module
  discard clock_gettime(0.ClockId, result)

proc toUidSet*(strs: seq[string]): HashSet[Uid] =
  ##Just parse some ints into typed Uids
  when NimVersion < "0.20.0": result = initSet[Uid]()
  else: result = initHashSet[Uid]()
  for s in strs: result.incl s.parseInt.Uid

proc toGidSet*(strs: seq[string]): HashSet[Gid] =
  ##Just parse some ints into typed Gids
  when NimVersion < "0.20.0": result = initSet[Gid]()
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
    when NimVersion < "0.20.0": result = initTable[Id, string]()
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

proc readlink*(p: string, err=stderr): string =
  ##Call POSIX readlink reliably: Start with a nominal size buffer & loop while
  ##the answer may have been truncated.  (Could also pathconf(p,PC_PATH_MAX)).
  result = newStringOfCap(512)
  var nBuf = 256
  var n = nBuf
  while n == nBuf:        #readlink(2) DOES NOT NUL-term, but Nim does, BUT it
    nBuf *= 2             #..is inaccessible to user-code.  So, the below does
    result.setLen(nBuf)   #..not need the nBuf + 1 it would in C code.
    n = readlink(p, cstring(result[0].addr), nBuf)
  if n <= 0:
    err.write "readlink(\"", $p, "\"): ", strerror(errno), "\n"
  else:
    result.setLen(n)

proc `$`*(st: Stat): string =
  ##stdlib automatic `$`(Stat) broken due to pad0 junk.
  "(dev: "     & $st.st_dev     & ", " & "ino: "    & $st.st_ino    & ", " &
   "nlink: "   & $st.st_nlink   & ", " & "mode: "   & $st.st_mode   & ", " &
   "uid: "     & $st.st_uid     & ", " & "gid: "    & $st.st_gid    & ", " &
   "rdev: "    & $st.st_rdev    & ", " & "size: "   & $st.st_size   & ", " &
   "blksize: " & $st.st_blksize & ", " & "blocks: " & $st.st_blocks & ", " &
   "atim: "    & $st.st_atim    & ", " & "mtim: "   & $st.st_mtim   & ", " &
   "ctim: "    & $st.st_ctim    & ")"

proc stat2dtype*(st_mode: Mode): int8 =
  ##Convert S_ISDIR(st_mode) style dirent types to DT_DIR style.
  if    S_ISREG(st_mode): result = DT_REG
  elif  S_ISDIR(st_mode): result = DT_DIR
  elif  S_ISBLK(st_mode): result = DT_BLK
  elif  S_ISCHR(st_mode): result = DT_CHR
  elif  S_ISLNK(st_mode): result = DT_LNK
  elif S_ISFIFO(st_mode): result = DT_FIFO
  elif S_ISSOCK(st_mode): result = DT_SOCK
  else:                   result = DT_UNKNOWN

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

proc `==`*(a, b: PathId): bool = a.dev == b.dev and a.ino == b.ino
proc hash*(x: PathId): int = x.dev.int * x.ino.int
