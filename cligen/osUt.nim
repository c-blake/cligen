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

import std/[os, osproc, strtabs, strutils, dynlib, times, stats, math]
type csize = uint

proc isatty(f: File): bool =
  when defined(posix):
    proc isatty(fildes: FileHandle): cint {.importc:"isatty",header:"unistd.h".}
  else:
    proc isatty(fildes: FileHandle): cint {.importc:"_isatty",header:"io.h".}
  result = isatty(getFileHandle(f)) != 0'i32

proc perror*(x: cstring, len: int, err=stderr) =
  ## Clunky w/spartan msgs, but allows safe output from OpenMP || blocks.
  if err == nil: return
  proc strlen(a: cstring): csize {.importc: "strlen", header: "<string.h>" .}
  let errno  = int(osLastError())
# var sys_errlist {.importc: "sys_errlist", header: "<stdio.h>".}: cstringArray
# var sys_nerr {.importc: "sys_nerr", header: "<stdio.h>".}: cint
# let errstr = if errno < int(sys_nerr): sys_errlist[errno] #XXX sys_*err always
#              else: cstring("errno with no sys_errlist")   #nil for some reason
  proc strerror(n: cint): cstring {.importc: "strerror", header: "<string.h>".}
  let errstr = strerror(cint(errno))  #XXX docs claim strerror is not MT-safe,
  let errlen = strlen(errstr)         #    but it sure seems to be on Linux.
  discard err.writeBuffer(pointer(x), len)
  err.write ": "
  discard err.writeBuffer(errstr, errlen)
  err.write "\n"

proc useStdin*(path: string): bool =
  ## Decide if ``path`` means stdin ("-" or "" and ``not isatty(stdin)``).
  path in ["-", "/dev/stdin"] or (path.len == 0 and not stdin.isatty)

proc c_getdelim*(p: ptr cstring, nA: ptr csize, dlm: cint, f: File): int {.
  importc: "getdelim", header: "<stdio.h>".}

proc free(pointr: cstring) {.importc: "free", header: "<stdlib.h>".}
iterator getDelim*(f: File, dlm: char='\n'): string =
  ## Efficient file line/record iterator using POSIX getdelim
  var cline: cstring
  var nAlloc: csize
  var res: string
  while true:
    let length = c_getdelim(cline.addr, nAlloc.addr, cint(dlm), f)
    if length == -1: break
    res.setLen(length - 1)      #-1 => remove dlm char like system.lines()
    if length > 1:
      copyMem(addr res[0], cline, length - 1)
    yield res
  free(cline)

iterator getDelims*(f: File, dlm: char='\n'): (cstring, int) =
  ## Like `getDelim` but yield `(ptr, len)` not auto-built Nim string.
  ## Note that unlike `lines` or `getDelim`, `len` always *includes* `dlm`.
  ##
  ## .. code-block:: nim
  ##  for (s, n) in stdin.getDelims: # or proc toNimStr(str: cstring, len: int)
  ##    discard toOpenArray[char](cast[ptr UncheckedArray[char]](s), 0, n-1).len
  var s: cstring
  var room: csize
  while (let n = c_getdelim(s.addr, room.addr, cint(dlm), f); n) + 1 > 0:
    yield (s, n)
  s.free

iterator getLenPfx*[T: SomeNumber](f: File): string =
  ## Like `getDelim` but "parse" length-prefixed values where a native-endian
  ## format binary length prefix is `SomeNumber`.  *Caller is responsible for
  ## specifying the right numeric type*, but format is simple & 8-bit clean.
  var s: string
  var len: T
  while f.ureadBuffer(len.addr, len.sizeof) == len.sizeof:
    let n = len.int
    s.setLen n
    if f.ureadBuffer(s[0].addr, n) < n: break
    yield s

proc fileStrings*(path: string, delim: char): auto =
  ## Return an iterator yielding ``delim``-delimited records in file ``path``.
  ## Note ``path = "/"`` is equivalent to a Unix ``path = "/dev/null"``.
  result = iterator(): string =
    if path.useStdin:
      for entry in getDelim(stdin, delim): yield entry
    elif path.len > 0 and path != "/":
      for entry in getDelim(open(path), delim): yield entry

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

proc uriteBuffer*(f: File, buffer: pointer, len: Natural): int {.inline.} =
  ## Unlocked (i.e. single threaded) libc `writeBuffer` (maybe Linux-only).
  when defined(linux) and not defined(android):
    proc c_fwrite(buf: pointer, size, n: csize, f: File): cint {.
            importc: "fwrite_unlocked", header: "<stdio.h>".}
  else:
    proc c_fwrite(buf: pointer, size, n: csize, f: File): cint {.
            importc: "fwrite", header: "<stdio.h>".}
  result = c_fwrite(buffer, 1, len.csize, f)

proc urite*(f: File, s: string) {.inline.} =
  ## Unlocked (i.e. single threaded) libc `write` (maybe Linux-only).
  if uriteBuffer(f, cstring(s), s.len) != s.len:
    raise newException(IOError, "cannot write string to file")

proc urite*(f: File, a: varargs[string, `$`]) {.inline.} =
  ## Unlocked (i.e. single threaded) libc `write` (maybe Linux-only).
  for x in items(a): urite(f, x)

proc replacingUrite*(f: File, s: string, eor: char, subEor: string) =
  ## Unlocked write `s` to `f` replacing any `eor` char with `subEor`.
  var off = 0
  while true:
    if (let ix = s.find(eor, start=off); ix >= 0):
      discard f.uriteBuffer(s[off].unsafeAddr, ix - off)
      discard f.uriteBuffer(subEor[0].unsafeAddr, subEor.len)
      off = ix + 1
    else:
      discard f.uriteBuffer(s[off].unsafeAddr, s.len - off)
      return

proc cfeof(f: File): cint {.importc: "feof", header: "<stdio.h>".}
proc eof*(f: File): bool {.inline.} = f.cfeof != 0

template outu*(a: varargs[string, `$`]) = stdout.urite(a)
  ## Like `stdout.write` but using fwrite_unlocked

template erru*(a: varargs[string, `$`]) = stderr.urite(a)
  ## Like `stderr.write` but using fwrite_unlocked

proc ureadBuffer*(f: File, buffer: pointer, len: Natural): int {.inline.} =
  when defined(linux) and not defined(android):
    proc c_fread(buf: pointer, size, n: csize, f: File): cint {.
            importc: "fread_unlocked", header: "<stdio.h>".}
  else:
    proc c_fread(buf: pointer, size, n: csize, f: File): cint {.
            importc: "fread", header: "<stdio.h>".}
  result = c_fread(buffer, 1, len.csize, f)

proc simplifyPath*(path: string, collapseDotDot=false): string =
  ##``"././hey///ho/./there/"`` => ``"hey/ho/there/"``.  Result always ends with
  ##``'/'`` as source does (it's an easy client check & setLen to remove it).
  ##If ``collapseDotDot`` then also delete ``foo/.. pairs`` which can alter the
  ##behavior of paths in the presence of symbolic links to directories.
  result = newStringOfCap(path.len)
  if path.startsWith($DirSep): result.add(DirSep)
  for component in path.split(DirSep):
    if component == "" or component == ".": continue  #nix empty & identity
    if collapseDotDot and component == ".." and result.len > 0:
      result.setLen(result.len - 1)                   #maybe nix foo/.. pairs
      continue
    result.add(component)
    result.add(DirSep)
  if result.len > 0:
    if not path.endsWith($DirSep):
      result.setLen(result.len - 1)
  else:
    result = "." & (if path.endsWith($DirSep): $DirSep else: "")

proc loadSym*(x: string): pointer =
  ## split ``x`` on ``':'`` into library:symbol parts, ``dynlib.loadLib`` the
  ## library and then ``dynlib.symAddr`` the symbol.  Returns the pointer or nil
  ## if either operation fails.
  let cols = x.split(':')
  if cols.len != 2:
    stderr.write("\"" & x & "\" not of form <lib.so>:<func>\n"); return
  let lib = loadLib(cols[0])
  if lib == nil:
    stderr.write("could not loadLib \"" & cols[0] & "\"\n"); return
  let sym = symAddr(lib, cols[1].cstring)
  if sym == nil:
    stderr.write("could not find \"" & cols[1] & "\"\n")
  sym

template timeIt*(output: untyped, label: string, unit=1e-6, places=3,
                 sep="\n", reps=1, body: untyped) =
  ## A simple benchmark harness.  ``output`` should be something like ``echo``
  ## or ``stdout.write`` depending on desired formatting.  ``label`` comes
  ## before time(``reps == 1``)|time statistics(``rep > 1``), while ``sep``
  ## comes after the numbers.
  var dt: RunningStat
  for r in 1..reps:
    let t0 = epochTime()
    body
    dt.push (epochTime() - t0)/unit
  if reps > 1:
    output label, " ", formatFloat(dt.min, ffDecimal, places), "..",
           formatFloat(dt.max, ffDecimal, places), " ",
           formatFloat(dt.mean, ffDecimal, places),
           " +- ",    # Report standard deviation *of the above mean*
           formatFloat(sqrt(dt.varianceS / dt.n.float), ffDecimal, places),
           sep
  else:
    output label, " ", formatFloat(dt.sum, ffDecimal, places), sep

proc writeNumberToFile*(path: string, num: int) =
  ## Best effort attempt to write a single number to a file.
  try:
    let f = open(path, fmWrite)
    f.write $num, '\n'
    f.close
  except:
    stderr.write "cannot open \"", path, "\" to write ", $num, '\n'

var vIOFBF {.importc: "_IOFBF", header: "stdio.h", nodecl.}: cint
var vIOLBF {.importc: "_IOLBF", header: "stdio.h", nodecl.}: cint
var vIONBF {.importc: "_IOFBF", header: "stdio.h", nodecl.}: cint
let IOFBF* = vIOFBF
let IOLBF* = vIOLBF
let IONBF* = vIONBF
proc c_setvbuf*(f: File, buf: pointer, mode: cint, size: csize): cint {.
  importc: "setvbuf", header: "<stdio.h>", tags: [].}

proc open*(fd: cint, mode=fmRead, bufMode=IOFBF, bufSize=4096): File =
  ## Make File from OS-level handle `fd` w/specific mode, buffer mode & size.
  if not result.open(fd, mode):
    raise newException(IOError, "cannot open fd " & $fd & " for mode " & $mode)
  discard c_setvbuf(stdout, nil, bufMode, bufSize.csize)

when defined(linux) or defined(macosx) or defined(freebsd) or defined(openbsd):
  import posix
when defined(linux):
  when defined(tcc): {.passc: "-D_GNU_SOURCE".}
  type CPUSet*{.importc: "cpu_set_t", header: "<sched.h>", final,pure.} = object
    discard # Need impl, but it is ignored; CPUSet=cpu_set_t, including sizeof
  proc cpu_zero*(set: ptr CPUSet) {.importc: "CPU_ZERO", header: "<sched.h>".}
  proc cpu_set*(cpu: cint; set: ptr CPUSet)
          {.importc: "CPU_SET", header: "<sched.h>".}
  proc getcpu*: cint {.importc: "sched_getcpu", header: "<sched.h>".}
  proc sched_setaffinity*(pid: Pid; sz: csize; mask: ptr CPUSet): cint
          {.importc: "sched_setaffinity", header: "<sched.h>".}

  proc setAffinity*(cpus: openArray[cint] = []) =
    ## Pin current thread to CPUs; No arg is like `setaffinity [getcpu()]`.
    var cs: CPUSet #; cpu_zero(cs.addr)
    if cpus.len == 0:
      cpu_set(getcpu(), cs.addr)
    else:
      for cpu in cpus:
        cpu_set(cpu.cint, cs.addr)
    discard sched_setaffinity(0.Pid, cs.sizeof.csize, cs.addr)

proc splitPathName*(path: string, shortestExt=false):
    tuple[dir, name, ext: string] =
  ## Like `os.splitFile` but return longest extensions not shortest (unless
  ## `shortestExt`).  E.g. `"/a/b/c.tar.gz"` => `("/a/b", "c", ".tar.gz")`, but
  ## with `shortest` would be `("/a/b", "c.tar", ".gz")`.
  var namePos = -1
  var dotPos  = -1
  for i in countdown(path.len - 1, 0):  # find start of last path component
    if path[i] in {DirSep, AltSep}:
      namePos = i; break                # *including* the separator
  for i in namePos + 1 ..< path.len:    # find extension within final component
    if path[i] == ExtSep:
      dotPos = i                        # stop @first = longest such extension
      if not shortestExt: break         # or @last = shortest such extension
  if namePos >= 0:
    result.dir = path[0..namePos]
  namePos.inc                           # unconditional: not found => 0
  if dotPos >= 0:
    result.name = path[namePos..dotPos-1]
    result.ext  = path[dotPos..^1]
  else:                                 # not found/no extension
    result.name = path[namePos..^1]
  if result.dir.len > 1:                # strip trailing DirSep except for root
    result.dir.setLen result.dir.len - 1

proc mkdirP*(path: string) =
  ## Create all parent dirs and path itself like Unix `mkdir -p foo/bar/baz`.
  if path.len == 0: return              # nothing to do => must have succeeded
  var path = path
  var sep: int
  while sep != -1:
    sep = path.find(DirSep, sep + 1)
    discard existsOrCreateDir(if sep > 0: path[0..<sep] else: path)

proc mkdirTo*(path: string) =
  ## Ensure leading directory prefix of `path` exists.
  let (dir, _, _) = splitPathName(path)
  if dir.len > 0: mkdirP(dir)

proc mkdirOpen*(path: string, mode=fmRead, bufSize = -1): File =
  ## Wrapper around system.open that ensures leading directory prefix exists.
  mkdirTo(path)
  open(path, mode, bufSize)

template popent(cmd, path, bufSize, mode, modeStr, dfl, dflStr): untyped =
  when defined(Windows):
    proc popen(a1, a2: cstring): File {.importc: "_popen".}
    let modeExtra = "b"
  else:
    let modeExtra = ""
  if cmd.len > 0:
    let c = cmd % path                  # Q: Also export $INPUT?
    if (let f = popen(c.cstring, cstring(modeStr & modeExtra)); f != nil):
      if bufSize != -1: discard c_setvbuf(f, nil, 0.cint, bufSize.csize)
      result = f
    else: raise newException(OSError, "cannot popen: \"" & c & "\"")
  elif path.len == 0 or path == "/dev/std" & dflStr:
    if bufSize != -1:                   # typically cancels any pending IO!
      discard c_setvbuf(dfl, nil, 0.cint, bufSize.csize)
    result = dfl
  else: result = open(path, mode, bufSize)

proc popenr*(cmd: string, path="", bufSize = -1): File =
  ## If `cmd.len==0` this is like regular `open(mode=fmRead)` except that "" or
  ## "/dev/stdin" are in-line translated to return `stdin`.  It otherwise wraps
  ## `popen(cmd % path, "rb")`.  So, $1 is how users place `path` in `cmd`.
  popent cmd, path, bufSize, fmRead, "r", stdin, "in"

proc popenw*(cmd: string, path="", bufSize = -1): File =
  ## If `cmd.len==0` this is like regular `open(mode=fmWrite)` except that "" or
  ## "/dev/stdout" are in-line translated to return `stdout`. It otherwise wraps
  ## `popen(cmd % path,"wb")`.  So, $1 is how users place `path` in `cmd`.
  popent cmd, path, bufSize, fmWrite, "w", stdout, "out"

proc pclose*(f: File, cmd: string): cint =
  ## Clean-up for `popen[rw]`.  Returns exit status of popen()d command.
  when defined(Windows):
    proc pclose(a: File): cint {.importc: "_pclose".}
  if cmd.len > 0: f.pclose else: (f.close; 0.cint) # WEXITSTATUS(result)

proc fileNewerThan*(a, b: string): bool =
  ## True if both path `a` & `b` exist and `a` is newer
  try: result = getLastModificationTime(b) < getLastModificationTime(a)
  except: discard

proc fileOlderThan*(a, b: string): bool =
  ## True if both path `a` & `b` exist and `a` is older
  try: result = getLastModificationTime(a) < getLastModificationTime(b)
  except: discard

proc clearDir*(dir: string) =
  ## Best effort removal of the *contents* of `dir`, but not `dir` itself.
  for path in walkPattern(dir/"*"):
    try: removeFile path
    except: removeDir path

import algorithm
proc walkPatSorted*(pattern: string): seq[string] =
  ## This is a glob/filename generation operation but returning a sorted `seq`
  ## the way most Unix shells would.
  for path in walkPattern(pattern): result.add path
  result.sort

proc touch*(path: string) =
  ## Create `path` or update its timestamp to the present - if possible.
  let tm = now().toTime
  if not fileExists(path):
    try: close(open(path, fmWrite))
    except: erru "could not create ", path; return
  try: setLastModificationTime path, tm
  except: erru "could not update time for ", path

import tables
var outs: Table[string, File]

proc autoOpen*(path: string, mode=fmWrite, bufSize = -1): File =
  ## For callers in expressional situations to open files on-demand.
  proc up(f: var File; path: string): File =
    if f == nil: f = mkdirOpen(path, mode, bufSize)
    f
  outs.mgetOrPut(path, nil).up(path)

proc autoClose* =
  ## Close all files opened so far by autoOpen.
  for path, f in outs: (if f != nil: f.close)
  outs.clear

proc rdRecs*(fd: cint, buf: var string, eor='\0', n=16384): int =
  ## Like read but loop if `end!=eor` (growing `buf` to multiples of `n`).  In
  ## effect, this reads an integral number of recs - which must still be split!
  var o, nR: int
  while (nR = read(fd, buf[o].addr, buf.len - o); nR>0 and buf[o+nR-1] != eor):
    o += nR
    buf.setLen buf.len + n                      # Keeps total len multiple of n,
  result = if nR <= 0: nR else: o+nR            #..but `buf` gets trailing junk.

proc uRd*[T](f: File, ob: var T): bool =
  ## Unlocked read flat object `ob` from `File`.
  f.ureadBuffer(ob.addr, ob.sizeof) == ob.sizeof

proc uWr*[T](f: File, ob: var T): bool =
  ## Unlocked write flat object `ob` to `File`.
  f.uriteBuffer(ob.addr, ob.sizeof) == ob.sizeof

proc wrOb*[T](fd: cint, ob: T): int = fd.write(ob.unsafeAddr, T.sizeof)
  ## Write flat object `ob` to file handle/descriptor `fd`.

proc wr*[T](fd: cint, ob: T): int {.deprecated: "use `wrOb`".} = fd.wrOb ob

proc wr0term*(fd: cint, buf: string): int =
  ## Write `buf` as a NUL-terminated string to `fd`.
  fd.write(buf[0].unsafeAddr.cstring, buf.len + 1)

proc wrLine*(fd: cint, buf: string): int =
  ## Write `buf` & then a single newline atomically (`writev` on Linux).
  let nl = '\n'
  let iov = [ IOVec(iov_base: buf[0].unsafeAddr, iov_len: buf.len.csize_t),
              IOVec(iov_base: nl.unsafeAddr    , iov_len: 1) ]
  writev(fd, iov[0].unsafeAddr, 2)

proc wrLenBuf*(fd: cint, buf: string): int =
  ## Write `int` length prefix & `buf` data atomically (`writev` on Linux).
  let n = buf.len
  let iov = [ IOVec(iov_base: n.unsafeAddr     , iov_len: n.sizeof.csize_t),
              IOVec(iov_base: buf[0].unsafeAddr, iov_len: buf.len.csize_t) ]
  writev(fd, iov[0].unsafeAddr, 2)

proc wrLenSeq*[T](fd: cint, s: seq[T]): int =
  ## Write `int` length prefixed data of a `seq[T]` atomically (`writev` on Linux),
  ## where `T` are either flat objects or tuples of flat objects (no indirections
  ## allowed).
  let n = s.len * sizeof(T)
  let iov = [ IOVec(iov_base: n.unsafeAddr   , iov_len: n.sizeof.csize_t),
              IOVec(iov_base: s[0].unsafeAddr, iov_len: n.csize_t) ]
  writev(fd, iov[0].unsafeAddr, 2)

proc lgBold*(f: File, s: string) = f.write "\e[1m", s, "\e[22m"
  ## Log to a `File`, `f` with ANSI SGR bold.

proc lgInv*(f: File, s: string) = f.write "\e[7m", s, "\e[27m"
  ## Log to a `File`, `f` with ANSI SGR inverse.

proc run*(cmd: openArray[string], env: StringTableRef=nil, opts={poEchoCmd,
          poUsePath}, dryRun=false, logFile=stderr, logWrite=lgBold): int =
  ## Wrap a sync(`waitForExit`) `os.startProcess` BUT only print (if `dryRun`),
  ## default to use PATH & echo & allow log destination/embellishment overrides.
  if poEchoCmd in opts and logFile != nil:
    logFile.logWrite cmd.join(" "); logFile.write '\n'
  if not dryRun:
    startProcess(cmd[0], "", cmd[1..^1], env, opts - {poEchoCmd}).waitForExit
  else: 0
