## Module similar to stdlib memfiles but (at the moment) posix only, and with
## exception-free interface which can help with multi-thread safety inside `||`
## blocks. Also adds a `noShrink` safeguard, supports write-only memory, is
## layered differently, has non-system.open-colliding type constructors, and
## uses `.len` instead of `.size` for consistency with other Nim things.

import std/[posix, os], ./mslice # cmemcmp mSlices
export PROT_READ, PROT_WRITE, PROT_EXEC, MAP_SHARED, MAP_PRIVATE, MAP_POPULATE

type
  MFile* = object   ## Like MemFile but safe in an MT-environment
    fd*   : cint    ## open file handle or -1 if not open
    st*   : Stat    ## File metadata at time of open
    prot* : cint    ## Map Protection
    flags*: cint    ## Map Flags (-1 => not open)
    mslc* : MSlice  ## (mem, len) of file
  csize = uint

proc mem*(mf: MFile): pointer = mf.mslc.mem ## accessor to use MFile like MSlice
proc len*(mf: MFile): int     = mf.mslc.len ## accessor to use MFile like MSlice
proc `mem=`*(mf: var MFile, m: pointer) = mf.mslc.mem = m ## accessor to use MFile like MSlice
proc `len=`*(mf: var MFile, n: int)     = mf.mslc.len = n ## accessor to use MFile like MSlice

proc getpagesize(): cint {. importc: "getpagesize", header: "<unistd.h>" .}
let pagesize = getpagesize()

proc perror(x: cstring, len: int, err=stderr) =
  if err == nil: return
  proc strlen(a: cstring): uint {.header: "string.h".}
  proc strerror(n: cint): cstring {.header: "string.h".}
  let errstr = strerror(cint(osLastError()))
  let errlen = strlen(errstr)
  discard err.writeBuffer(pointer(x), len); err.write ": "
  discard err.writeBuffer(errstr, errlen); err.write "\n"

proc mopen*(fd: cint; st: Stat, prot=PROT_READ, flags=MAP_SHARED, a=0.Off,
            b = Off(-1), allowRemap=false, noShrink=false, err=stderr): MFile =
  ## mmap(2) wrapper to simplify life.  Byte range [a,b) of the file pointed to
  ## by 'fd' translates to [result.mem ..< .len).
  var b0 = Off(b)                           #Will be adjusting this, pre-map
  if fd == -1: return
  result.fd    = fd
  result.st    = st
  result.prot  = prot
  result.flags = flags
  if (prot and PROT_WRITE) != 0 and Off(st.st_size) != b and b != Off(-1):
    if (b > Off(st.st_size) or not noShrink) and flags != MAP_PRIVATE:
      if ftruncate(fd, b) == -1:            #Writable & too small => grow
        perror cstring("ftruncate"), 9, err
        return                              #Likely passed non-writable fd
      discard fstat(fd, result.st)          #Refresh st data ftrunc; Cannot fail
  elif b == Off(-1):                        #Do special whole file mode
    b0 = Off(result.st.st_size)
  b0 = min(b0, Off(result.st.st_size))      #Do not exceed file sz
  if b0 > a:                                #Leave .mem nil & .len==0 if empty
    let prot = if flags == MAP_PRIVATE: (PROT_READ or PROT_WRITE) else: prot
    result.mslc.len = int(b0 - a)
    result.mslc.mem = mmap(nil, result.mslc.len, prot, flags, fd, Off(a))
    if result.mslc.mem == cast[pointer](MAP_FAILED):
      perror cstring("mmap"), 4, err
      result.mslc.mem = nil
      return

proc mopen*(fd: cint, prot=PROT_READ, flags=MAP_SHARED, a=0, b = Off(-1),
            allowRemap=false, noShrink=false, err=stderr): MFile =
  ## Init map for already open ``fd``.  See ``mopen(cint,Stat)`` for details.
  if fd == -1:
    return
  if fstat(fd, result.st) == -1:
    perror cstring("fstat"), 5, err
    return
  if not S_ISREG(result.st.st_mode):  #Even symlns should fstat to ISREG. Quiet
    return                            #error in case client trying /dev/stdin.
  result = mopen(fd, result.st, prot, flags, a, b, allowRemap, noShrink, err)

proc mopen*(path: string, prot=PROT_READ, flags=MAP_SHARED, a=0, b = -1,
            allowRemap=false, noShrink=false, perMask=0o666, err=stderr): MFile=
  ## Init map for ``path``.  ``See mopen(cint,Stat)`` for mapping details.
  ## This proc also creates a file, if necessary, with permission ``perMask``.
  var oflags: cint
  if path.len == 0: return
  if flags == MAP_PRIVATE:
    oflags = O_RDONLY or O_NONBLOCK
  elif (prot and (PROT_READ or PROT_WRITE)) == (PROT_READ or PROT_WRITE):
    oflags = O_RDWR or O_CREAT or O_NONBLOCK
  elif (prot and PROT_READ) != 0:
    oflags = O_RDONLY or O_NONBLOCK
  elif (prot and PROT_WRITE) != 0:    #Write-only memory is only rarely useful
    oflags = O_WRONLY or O_CREAT or O_NONBLOCK
  let fd = open(path, oflags, perMask.cint)
  if fd == -1:
    perror cstring("open"), 4, err; return
  result = mopen(fd, prot, flags, a, b, allowRemap, noShrink)
  if not allowRemap:
    if close(fd) == -1: perror cstring("close"), 5, err
    result.fd = -1

proc close*(mf: var MFile, err=stderr) =
  ## Release memory acquired by MFile mopen()s
  if mf.fd != -1:
    if close(mf.fd) == -1: perror cstring("close"), 5, err
    mf.fd = -1
  if mf.mslc.mem != nil and munmap(mf.mslc.mem, mf.mslc.len) == -1:
    perror cstring("munmap"), 6, err
  mf.mslc.mem = nil

proc close*(mf: MFile, err=stderr) =
  ## Release memory acquired by MFile mopen()s; Allows let mf = mopen()
  if mf.fd != -1:
    if close(mf.fd) == -1: perror cstring("close"), 5, err
  if mf.mem != nil and munmap(mf.mem, mf.len) == -1:
    perror cstring("munmap"), 6, err

proc resize*(mf: var MFile, newFileSize: int, err=stderr): int =
  ## Resize & re-map file underlying an ``allowRemap MFile``. ``.mem`` will
  ## likely change.  **Note**: this assumes entire file is mapped @off=0.
  if mf.fd == -1:
    perror cstring("mopen needs allowRemap"), 22, err
    return -1
  if ftruncate(mf.fd, newFileSize) == -1:
    perror cstring("ftruncate"), 9, err
    return -1
  when defined(linux):                          #Maybe NetBSD, too?
    proc mremap(old: pointer; oldSize, newSize: csize; flags: cint): pointer {.
      importc: "mremap", header: "<sys/mman.h>" .}
    let newAddr = mremap(mf.mem, csize(mf.len), csize(newFileSize), cint(1))
    if newAddr == cast[pointer](MAP_FAILED):
      perror cstring("mremap"), 6, err
      return -1
  else: #On Linux mremap can be over 100X faster than this munmap+mmap cycle.
    if munmap(mf.mem, mf.len) != 0:
      perror cstring("munmap"), 6, err
      return -1
    let newAddr = mmap(nil, newFileSize, mf.prot, mf.flags, mf.fd, 0)
    if newAddr == cast[pointer](MAP_FAILED):
      perror cstring("mmap"), 4, err
      return -1
  mf.mslc.mem = newAddr
  mf.mslc.len = newFileSize

proc add*[T: SomeInteger](mf: var MFile, ch: char, off: var T) = # -> mfile
  ## Append `ch` to `mf`, resizing if necessary and updating offset `off`.
  if off.int + 1 == mf.len: discard mf.resize mf.len * 2
  cast[ptr char](mf.mem +% off.int)[] = ch
  inc off

proc add*[T: SomeInteger](mf: var MFile, ms: MSlice, off: var T) = # -> mfile
  ## Append `ms` to `mf`, resizing if necessary and updating offset `off`.
  if off.int + ms.len >= mf.len: discard mf.resize mf.len * 2
  copyMem mf.mem +% off.int, ms.mem, ms.len
  inc off, ms.len

proc inCore*(mf: MFile): tuple[resident, total: int] =
  proc mincore(adr: pointer, length: csize, vec: cstring): cint {.
         importc: "mincore", header: "<sys/mman.h>" .}
  result.total = (mf.len + pagesize - 1) div pagesize #limit buffer to 64K?
  var resident = newString(result.total)
  if mincore(mf.mem, mf.len.csize, resident.cstring) != -1: #nsleep on EAGAIN?
    for page in resident:
      if (page.int8 and 1) != 0: result.resident.inc

proc `<`*(a,b: MFile): bool = cmemcmp(a.mem, b.mem, min(a.len, b.len).csize) < 0

proc `==`*(a,b: MFile): bool = a.len==b.len and cmemcmp(a.mem,b.mem,a.len.csize)==0

proc `==`*(a: MFile, p: pointer): bool = a.mem==p

proc toMSlice*(mf: MFile): MSlice = mf.mslc
  ## MSlice field accessor for consistency with toMSlice(string)

iterator mSlices*(mf: MFile, sep='\l', eat='\r'): MSlice =
  for ms in mSlices(mf.toMSlice, sep, eat):
    yield ms

iterator lines*(mf:MFile, buf:var string, sep='\l', eat='\r'): string =
  ## Copy each line in ``mf`` to passed ``buf``, like ``system.lines(File)``.
  ## ``sep``, ``eat``, and delimiting logic is as for ``mslice.mSlices``, but
  ## Nim strings are returned.  Default parameters parse lines ending in either
  ## Unix(\\l) or Windows(\\r\\l) style on on a line-by-line basis (not every
  ## line needs the same ending).  ``sep='\\r', eat='\\0'`` parses archaic
  ## MacOS9 files.
  ##
  ## .. code-block:: nim
  ##   var buffer: string = ""
  ##   for line in lines(mopen("foo"), buffer): echo line
  if mf.mem != nil:
    for ms in mSlices(mf, sep, eat):
      ms.toString buf
      yield buf

iterator lines*(mf: MFile, sep='\l', eat='\r'): string =
  ## Exactly like ``lines(MFile, var string)`` but yields new Nim strings.
  ##
  ## .. code-block:: nim
  ##   for line in lines(mopen("foo")): echo line   #Example
  var buf = newStringOfCap(80)
  for line in lines(mf, buf, sep, eat): yield buf

iterator rows*(mf: MFile, s: Sep, row: var seq[MSlice], n=0, sep='\l',
               eat='\r'): seq[MSlice] =
  ##Like ``lines(MFile)`` but also split each line into columns with ``Sep``.
  if mf.mem != nil:
    for line in mSlices(mf, sep, eat):
      s.split(line, row, n)
      yield row

iterator rows*(mf: MFile, s: Sep, n=0, sep='\l', eat='\r'): seq[MSlice] =
  ## Exactly like ``rows(MFile, Sep)`` but yields new Nim ``seq``s.
  var sq = newSeqOfCap[MSlice](n)
  for row in rows(mf, s, sq, n, sep, eat): yield sq

iterator rows*(f: File, s: Sep, row: var seq[string], n=0): seq[string] =
  ## Like ``lines(File)`` but also split each line into columns with ``Sep``.
  for line in lines(f):
    s.split(line, row, n)
    yield row

iterator rows*(f: File, s: Sep, n=0): seq[string] =
  ## Exactly like ``rows(File, Sep)`` but yields new Nim ``seq``s.
  var sq = newSeqOfCap[string](n)
  for row in rows(f, s, sq, n): yield sq

iterator getDelims(f: File, dlm: char='\n'): (cstring, int) =
  proc getdelim(p: ptr cstring, n: ptr uint, dlm: cint, f: File): int {.header: "stdio.h".}
  proc free(pointr: cstring) {.header: "stdlib.h".}
  var s: cstring
  var room: csize
  while (let n=getdelim(s.addr, room.addr, cint(dlm), f); n)+1 > 0: yield (s, n)
  s.free

var doNotUse: MFile
iterator mSlices*(path: string, sep='\l', eat='\r', keep=false,
                  err=stderr, mf: var MFile=doNotUse): MSlice =
  ##A convenient input iterator that ``mopen()``s path or if that fails falls
  ##back to ordinary file IO but constructs ``MSlice`` from lines. ``true keep``
  ##means MFile or strings backing MSlice's are kept alive for life of program
  ##unless you also pass `mf` which returns the `MFile` to close when unneeded.
  let mfl = mopen(path, err=err)    # MT-safety means cannot just use `mf`
  if mfl.mem != nil:
    for ms in mSlices(mfl.toMSlice, sep, eat):
      yield ms
    if mf.addr == doNotUse.addr:
      if not keep: mfl.close(err=err)
    else: mf = mfl
  else:
    if mf.addr != doNotUse.addr: mf.mslc.mem = nil; mf.fd = -1 # close => no-op
    try:
      let f = if path == "/dev/stdin": stdin else: open(path)
      for (cs, n) in f.getDelims:
        if n > 0 and cs[n-1] == '\n':
          cast[ptr UncheckedArray[char]](cs)[n-1] = '\0'
          yield MSlice(mem: cs, len: n - 1)
        else:
          yield MSlice(mem: cs, len: n)
      if f!=stdin: f.close() # stdin.close frees fd=0;Could be re-opened&confuse
    except IOError: perror "fopen", 5, err

proc findPathPattern*(pathPattern: string): string =
  ## Search directory containing pathPattern (or ".") for *first* matching name.
  ## Pattern matching is currently substring only.
  proc strstr(hay,needle: cstring): cstring {.importc, header: "<string.h>".}
  proc strlen(str: cstring): csize {.importc, header: "<string.h>".}
  var tmp  = pathPattern    #basename & dirname both write into buffer; So copy.
  let base = basename(tmp.cstring)  #Also, order matters: Call basename first.
  let dir  = dirname(tmp.cstring)
  if (let d = opendir(dir); d) != nil:
    while (let de = d.readdir; de) != nil:
      let mch = cast[cstring](de.d_name[0].addr)
      if strstr(mch, base) != nil:
        let nDir = int(strlen(dir))
        let nMch = int(strlen(mch))
        result.setLen nDir + 1 + nMch
        copyMem result[0].addr, dir, nDir
        result[nDir] = '/'
        copyMem result[nDir+1].addr, de.d_name[0].addr, nMch + 1
        break
    discard d.closedir

proc nSplit*(n: int, path: string, sep='\n', prot=PROT_READ, flags=MAP_SHARED):
       tuple[mf: MFile; parts: seq[MSlice]] =
  ## Split seekable file @`path` into `n` roughly equal `sep`-delimited parts
  ## with any separator char included in slices. Caller should close `result.mf`
  ## (which is `nil` on failure) when desired.  `result.len` can be < `n` for
  ## small file sizes (in number of `sep`s).  For IO efficiency, subdivision is
  ## done by bytes as a guess.  So, this is fast, but accuracy is limited by
  ## statistical regularity.
  result.mf = mopen(path, prot, flags, allowRemap=false, noShrink=true)
  if result.mf.mem != nil:
    result.parts = n.nSplit(result.mf.toMSlice, sep)
