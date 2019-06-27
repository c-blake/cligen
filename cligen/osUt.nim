## This module is a grab bag of utility code that is often useful interfacing
## between CLIs and the OS.  Example:
##
## .. code-block:: nim
##  proc something*(file="", delim='\n', paths: seq[string]): int =
##    ## Do example on paths which are the UNION of ``paths`` & optional
##    ## ``delim``-delimited input ``file`` (stdin if "-"|if "" & stdin not
##    ## a tty).  Eg., ``find -type f -print0|example -d\\x00 a b c``.
##    for path in both(fileStrings(file, delim), paths)(): discard
##  dispatch(something)

import os, posix, terminal, strutils, sets, tables, strformat, ./sysUt #`:=`

proc perror*(x: cstring, len: int) =
  ## Clunky w/spartan msgs, but allows safe output from OpenMP || blocks.
  proc strlen(a: cstring): csize {.importc: "strlen", header: "<string.h>" .}
  let errno  = int(osLastError())
# var sys_errlist {.importc: "sys_errlist", header: "<stdio.h>".}: cstringArray
# var sys_nerr {.importc: "sys_nerr", header: "<stdio.h>".}: cint
# let errstr = if errno < int(sys_nerr): sys_errlist[errno] #XXX sys_*err always
#              else: cstring("errno with no sys_errlist")   #nil for some reason
  proc strerror(n: cint): cstring {.importc: "strerror", header: "<string.h>".}
  let errstr = strerror(cint(errno))  #XXX docs claim strerror is not MT-safe,
  let errlen = strlen(errstr)         #    but it sure seems to be on Linux.
  discard stderr.writeBuffer(pointer(x), len)
  stderr.write ": "
  discard stderr.writeBuffer(errstr, errlen)
  stderr.write "\n"

proc useStdin*(path: string): bool =
  ## Decide if ``path`` means stdin ("-" or "" and ``not isatty(stdin)``).
  result = (path == "-" or (path.len == 0 and not terminal.isatty(stdin)))

iterator getDelim*(stream: File, dlm: char='\n'): string =
  ## Efficient file line/record iterator using POSIX getdelim
  proc c_gd(p: ptr cstring, nA: ptr csize, dlm: cint, stream: File): int {.
    importc: "getdelim", header: "<stdio.h>".}
  proc free(pointr: cstring) {.importc: "free", header: "<stdlib.h>".}
  var cline: cstring
  var nAlloc: csize
  var res: string
  while true:
    let length = c_gd(cline.addr, nAlloc.addr, cint(dlm), stream)
    if length == -1: break
    res.setLen(length - 1)      #-1 => remove dlm char like system.lines()
    copyMem(addr res[0], cline, length - 1)
    yield res
  free(cline)

proc fileStrings*(path: string, delim: char): auto =
  ## Return an iterator yielding ``delim``-delimited records in file ``path``.
  let uSI = useStdin(path)
  result = iterator(): string =
    if uSI or path.len > 0:
      for entry in getDelim(if uSI: stdin else: system.open(path), delim):
        yield entry

proc both*[T](s: seq[T], it: iterator(): T): iterator(): T =
  ## Return an iterator yielding both seq elements and the passed iterator.
  result = iterator(): T =
    for e in s: yield e
    for e in it(): yield e

proc both*[T](it: iterator(): T, s: seq[T]): iterator(): T =
  ## Return an iterator yielding both seq elements and the passed iterator.
  result = iterator(): T =
    for e in it(): yield e
    for e in s: yield e

proc uriteBuffer*(f: File, buffer: pointer, len: Natural): int =
  proc c_fwrite(buf: pointer, size, n: csize, f: File): cint {.
          importc: "fwrite_unlocked", header: "<stdio.h>".}
  result = c_fwrite(buffer, 1, len, f)

proc urite*(f: File, s: string) =
  if uriteBuffer(f, cstring(s), s.len) != s.len:
    raise newException(IOError, "cannot write string to file")

proc urite*(f: File, a: varargs[string, `$`]) =
  for x in items(a): urite(f, x)

proc getTime*(): Timespec =
  ##Placeholder to avoid `times` module
  discard clock_gettime(0.ClockId, result)

proc simplifyPath*(path: string): string =
  ##Make "././hey///ho/./there/" => "hey/ho/there/".  Result always ends with
  ##'/' as source does (it's an easy client check & setLen to remove it).  Note
  ##this does not do anything that requires following symbolic links.
  result = newStringOfCap(path.len)
  if path.startsWith("/"): result.add('/')
  var didSomething = false
  for component in path.split('/'):
    if component == "" or component == ".": continue
    result.add(component)
    result.add('/')
    didSomething = true
  if didSomething:
    if not path.endsWith("/"):
      result.setLen(result.len - 1)
  else:
    result = path

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

template defineIdentities(ids,Id,Entry,rewind,getident,en_id,en_nm) {.dirty.} =
  proc ids*(): Table[Id, string] =
    ##Populate Table[Id, string] with data from system account files
    when NimVersion < "0.20.0": result = initTable[Id, string]()
    rewind()
    var id: ptr Entry
    while (id := getident()) != nil:
      if id.en_id notin result:             #first entry wins, not last
        result[id.en_id] = $id.en_nm
defineIdentities(users, Uid, Passwd, setpwent, getpwent, pw_uid, pw_name)
defineIdentities(groups, Gid, Group, setgrent, getgrent, gr_gid, gr_name)

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

var lastBadDev = 0.Dev
proc getxattr*(path: string, name: string, dev: Dev=0): int =
  proc getxattr(path:cstring; name:cstring; value:pointer; size:csize): csize {.
      importc: "getxattr", header: "sys/xattr.h".}
  if dev == lastBadDev: errno = EOPNOTSUPP; return -1
  result = getxattr(path.cstring, name.cstring, nil, 0).int
  if result == -1 and errno == EOPNOTSUPP:
    lastBadDev = dev
