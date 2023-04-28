## Module similar to `std/memfiles` but better layered & no exceptions interface
## which can help w/fancy file making needs or safety inside `||` blocks.  Also
## adds `noShrink` safety, has non-system.open-colliding type constructor, uses
## `.len` (not `.size`) for more Nim-wide consistency & supports WO memory, and
## has FileInfo in the object (for various inspections).

when not declared(File): import std/syncio
import std/os, ./mslice, ./osUt # cmemcmp mSlices setFileSize,getDelims
when defined(windows):
  import winlean
  when useWinUnicode and defined(nimPreviewSlimSystem): import std/widestrs
  type Off* {.importc: "off_t", header: "<sys/types.h>".} = int64
  const PROT_READ* =1.cint; const PROT_WRITE* =2.cint; const PROT_EXEC* =4.cint
  const MAP_SHARED* = 1.cint; const MAP_PRIVATE* = 2.cint
  const MAP_POPULATE* = 32768.cint  # debatable..
else:
  import std/posix
  export PROT_READ, PROT_WRITE, PROT_EXEC, MAP_SHARED, MAP_PRIVATE, MAP_POPULATE
let PROT_RW* = PROT_READ or PROT_WRITE ## read-write is a common combination

type
  MFile* = object   ## Like MemFile but safe in an MT-environment
    fd*  : cint     ## open file|-1; open_osfhandle(fh,) on Win; FileHandle=cint
    fi*  : FileInfo ## File metadata at time of open
    when defined(windows): # .fd for getFileInfo but .fh setFileSize for other
      fh*: cint     ## Underlying OS File Handle; fdclose(fd) auto-closes this
      mh*: Handle   ## M)ap H)andle *CAUTION*: Windows specific public field
    prot* : cint    ## Map Protection
    flags*: cint    ## Map Flags (-1 => not open)
    mslc* : MSlice  ## (mem, len) of file
  csize = uint

proc `[]`*[A,B](mf: MFile, s: HSlice[A,B]): MSlice = mf.mslc[s]

proc mem*(mf: MFile): pointer = mf.mslc.mem ## accessor to use MFile like MSlice
proc len*(mf: MFile): int     = mf.mslc.len ## accessor to use MFile like MSlice
proc `mem=`*(mf: var MFile, m: pointer) = mf.mslc.mem = m ## use MFile ~ MSlice
proc `len=`*(mf: var MFile, n: int)     = mf.mslc.len = n ## use MFile ~ MSlice

when not defined(windows):
  proc getpagesize(): cint {. importc: "getpagesize", header: "<unistd.h>" .}
  let pagesize = getpagesize()

template doFdClose(fd, fh): untyped =
  if fd == cint(-1): -1
  else: (when defined(windows): fd.fdClose else: fd.close)

proc fdClose*(mf: MFile): int = doFdClose(mf.fd, mf.fh)
  ## Only release file handles underlying `mf`

proc fdClose*(mf: var MFile): int = ## Only release file handles underlying `mf`
  if doFdClose(mf.fd, mf.fh) != -1: mf.fd = -1  # invalidate on success

proc setSize(mf: MFile; old, new: int64): OSErrorCode =
  (when defined(windows): mf.fh else: mf.fd).setFileSize(old, new)

proc mopen*(fd,fh: cint; fi:FileInfo, prot=PROT_READ, flags=MAP_SHARED, a=0.Off,
            b = Off(-1), allowRemap=false, noShrink=false, err=stderr): MFile =
  ## mmap(2) wrapper to simplify life.  Byte range [a,b) of the file pointed to
  ## by 'fd' translates to [result.mem ..< .len).
  var b0 = Off(b)                           #Will be adjusting this, pre-map
  if fd == -1: return
  result.fd    = fd
  when defined(windows): result.fh = fh
  result.fi    = fi
  result.prot  = prot
  result.flags = flags
  if (prot and PROT_WRITE) != 0 and Off(fi.size) != b and b != Off(-1):
    if (b > Off(fi.size) or not noShrink) and flags != MAP_PRIVATE:
      if result.setSize(fi.size, b) != 0.OSErrorCode: # Writable&TooSmall=>grow
        perror cstring("setFileSize"), err; return # Likely non-writable fd
      try: result.fi = fd.getFileInfo       #Refresh st data ftrunc; Cannot fail
      except CatchableError: discard
  elif b == Off(-1):                        #Do special whole file mode
    b0 = Off(result.fi.size)
  b0 = min(b0, Off(result.fi.size))         #Do not exceed file sz
  if b0 > a:                                #Leave .mem nil & .len==0 if empty
    result.mslc.len = int(b0 - a)
    when defined(windows):
      let ro = (prot and PROT_READ) != 0 and (prot and PROT_WRITE) == 0
      result.mh = createFileMappingW(result.fh, nil,
        if ro: PAGE_READONLY else: PAGE_READWRITE, 0, 0, nil)
      if result.mh != 0:
        result.mem = mapViewOfFileEx(result.mh,
         if ro: FILE_MAP_READ else: FILE_MAP_READ or FILE_MAP_WRITE,
         int32(a shr 32), int32(a and 0xffffffff), result.mslc.len.WinSizeT,nil)
    else:
      let prot = if flags == MAP_PRIVATE: (PROT_READ or PROT_WRITE) else: prot
      result.mslc.mem = mmap(nil, result.mslc.len, prot, flags, fd, Off(a))
      if result.mslc.mem == cast[pointer](MAP_FAILED):
        result.mslc.mem = nil
        perror cstring("mmap"), err; return

proc mopen*(fh: cint, prot=PROT_READ, flags=MAP_SHARED, a=0, b = Off(-1),
            allowRemap=false, noShrink=false, err=stderr): MFile =
  ## Init map for already open `fh`.  See `mopen(cint, Stat)` for details.
  if fh == -1:  #NOTE: It is important to initialize .fd,.fh so that mopen(path)
    return      #      does NOT close(0 {default init}).
  result.fd = when defined(windows): open_osfhandle(fh, 0).cint else: fh
  try:
    result.fi = result.fd.getFileInfo
  except CatchableError: # LEAK: Win cannot fdclose(fd) WITHOUT closing `fh`!
    perror cstring("fstat"), err; return
  if result.fi.kind in {pcDir, pcLinkToDir}:
    perror cstring("directories are un-mmappable"), err; return  # Same LEAK
  mopen(result.fd, fh, result.fi, prot, flags, a, b, allowRemap, noShrink, err)

proc mopen*(path: string, prot=PROT_READ, flags=MAP_SHARED, a=0, b = -1,
            allowRemap=false, noShrink=false, perMask=0o666, err=stderr): MFile=
  ## Init map for ``path``.  ``See mopen(cint,Stat)`` for mapping details.
  ## This proc also creates a file, if necessary, with permission ``perMask``.
  if path.len == 0: return
  when defined(windows):
    let ro = (prot and PROT_READ) != 0 and (prot and PROT_WRITE) == 0
    template openFl(api, path): untyped = api(path,
        GENERIC_READ or (if ro: 0 else: GENERIC_WRITE), # READ or WRITE != ALL
        FILE_SHARE_READ or (if ro: 0 else: FILE_SHARE_WRITE), nil,
        if ro: OPEN_EXISTING else: CREATE_ALWAYS,
        if ro: FILE_ATTRIBUTE_READONLY else: FILE_ATTRIBUTE_NORMAL, 0)
    when useWinUnicode: (let fh = openFl(createFileW, path.newWideCString).cint)
    else: (let fh = openFl(createFileA, path).cint)
  else: # infer file open-flags from mapping flags
    let fl = if flags == MAP_PRIVATE: O_RDONLY                     # Read Only
             elif (prot and PROT_RW) == PROT_RW: O_RDWR or O_CREAT # Read-Write
             elif (prot and PROT_READ) != 0: O_RDONLY              # Read-Only
             elif (prot and PROT_WRITE) != 0: O_WRONLY or O_CREAT  # Write Only
             else: 0.cint
    let fh = open(path, fl or O_NONBLOCK, perMask.cint) # Stop specials blocking
  if fh == -1:
    perror cstring("open"), err; return
  result = mopen(fh, prot, flags, a, b, allowRemap, noShrink)
  if result.mem == nil or not allowRemap:
    if result.fdClose == -1: perror cstring("fdClose"), err
    result.fd = -1; when defined(windows): result.fh = -1

template doClose =
  if mf.fd != -1:
    if mf.fdClose == -1: perror cstring("close"), err
  if mf.mem == nil: return      # Nothing to do
  when defined(windows):
    if mf.mem.unmapViewOfFile == 0: perror cstring("unmapViewOfFile"), err
    if mf.mh.closeHandle == 0: perror cstring("closeMapHandle"), err
  else:
    if munmap(mf.mem, mf.len) == -1: perror cstring("munmap"), err

proc close*(mf: MFile, err=stderr) = doClose()
  ## Release memory acquired by MFile mopen()s; Allows let mf = mopen()

proc close*(mf: var MFile, err=stderr) =
  ## Release memory acquired by `mf` mopen()s; Sets fields to invalid.
  doClose(); mf.mslc.mem = nil; mf.fd = -1

proc resize*(mf: var MFile, newFileSize: int64, err=stderr): int =
  ## Resize & re-map file underlying an ``allowRemap MFile``. ``.mem`` will
  ## likely change.  **Note**: this assumes entire file is mapped @off=0.
  if mf.fd == -1 or (when defined(windows): mf.mh == 0 else: false):
    perror cstring("need valid `mf` with allowRemap"), err; return -1
  template editFileSize =
    if mf.setSize(mf.fi.size, newFileSize) != 0.OSErrorCode:
      perror cstring("editFileSize"), err; return -1
    mf.fi.size = newFileSize            #XXX Re-do getFileInfo|Deal w/rounding
  when defined(windows):                # Undo, re-make, re-do
    if mf.mem.unmapViewOfFile == 0 or mf.mh.closeHandle == 0:
      perror cstring("unmappingPResize"), err; return -1
    editFileSize()
    if (mf.mh = createFileMappingW(mf.fh,nil,PAGE_READWRITE,0,0,nil); mf.mh==0):
      perror cstring("createFileMappingW"), err; return -1
    let newAddr = mapViewOfFileEx(mf.mh, FILE_MAP_READ or FILE_MAP_WRITE, 0, 0,
                                  newFileSize.WinSizeT, nil)
    if newAddr == nil:
      perror cstring("mapViewOfFileEx"), err; return -1
  elif defined(linux):                  # Maybe also NetBSD?
    proc mremap(p: pointer; sz0, sz1: csize; flags: cint): pointer {.
           importc: "mremap", header: "sys/mman.h".}
    editFileSize()
    let newAddr = mremap(mf.mem, csize(mf.len), csize(newFileSize), cint(1))
    if newAddr == cast[pointer](MAP_FAILED):
      perror cstring("mremap"), err; return -1
  else: #On Linux mremap can be over 100X faster than this munmap+mmap cycle.
    if munmap(mf.mem, mf.len) != 0:
      perror cstring("munmap"), err; return -1
    editFileSize()
    let newAddr = mmap(nil, newFileSize.int, mf.prot, mf.flags, mf.fd, 0)
    if newAddr == cast[pointer](MAP_FAILED):
      perror cstring("mmap"), err; return -1
  mf.mslc.mem = newAddr
  mf.mslc.len = newFileSize.int

proc add*[T: SomeInteger](mf: var MFile, ch: char, off: var T) = # -> mfile
  ## Append `ch` to `mf`, resizing if necessary and updating offset `off`.
  if off.int + 1 == mf.len: discard mf.resize mf.len * 2
  cast[ptr char](mf.mem +! off.int)[] = ch
  inc off

proc add*[T: SomeInteger](mf: var MFile, ms: MSlice, off: var T) = # -> mfile
  ## Append `ms` to `mf`, resizing if necessary and updating offset `off`.
  if off.int + ms.len >= mf.len: discard mf.resize mf.len * 2
  copyMem mf.mem +! off.int, ms.mem, ms.len
  inc off, ms.len

proc inCore*(mf: MFile): tuple[resident, total: int] =
  when defined(windows): discard
  else:
    proc mincore(adr: pointer, length: csize, vec: cstring): cint {.
           importc: "mincore", header: "<sys/mman.h>" .}
    result.total = (mf.len + pagesize - 1) div pagesize #limit buffer to 64K?
    var resident = newString(result.total)
    if mincore(mf.mem, mf.len.csize, resident.cstring) != -1: #nsleep on EAGAIN?
      for page in resident:
        if (page.int8 and 1) != 0: result.resident.inc

proc `<`*(a,b: MFile): bool = cmemcmp(a.mem, b.mem, min(a.len, b.len).csize) < 0

proc `==`*(a,b:MFile): bool=a.len==b.len and cmemcmp(a.mem,b.mem,a.len.csize)==0

proc `==`*(a: MFile, p: pointer): bool = a.mem==p

proc toMSlice*(mf: MFile): MSlice = mf.mslc
  ## MSlice field accessor for consistency with toMSlice(string)

iterator mSlices*(mf: MFile, sep='\n', eat='\r'): MSlice =
  for ms in mSlices(mf.toMSlice, sep, eat):
    yield ms

iterator lines*(mf:MFile, buf:var string, sep='\n', eat='\r'): string =
  ## Copy each line in ``mf`` to passed ``buf``, like ``system.lines(File)``.
  ## ``sep``, ``eat``, and delimiting logic is as for ``mslice.mSlices``, but
  ## Nim strings are returned.  Default parameters parse lines ending in either
  ## Unix(\\n) or Windows(\\r\\n) style on on a line-by-line basis (not every
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

iterator lines*(mf: MFile, sep='\n', eat='\r'): string =
  ## Exactly like ``lines(MFile, var string)`` but yields new Nim strings.
  ##
  ## .. code-block:: nim
  ##   for line in lines(mopen("foo")): echo line   #Example
  var buf = newStringOfCap(80)
  for line in lines(mf, buf, sep, eat): yield buf

iterator rows*(mf: MFile, s: Sep, row: var seq[MSlice], n=0, sep='\n',
               eat='\r'): seq[MSlice] =
  ##Like ``lines(MFile)`` but also split each line into columns with ``Sep``.
  if mf.mem != nil:
    for line in mSlices(mf, sep, eat):
      s.split(line, row, n)
      yield row

iterator rows*(mf: MFile, s: Sep, n=0, sep='\n', eat='\r'): seq[MSlice] =
  ## Exactly like ``rows(MFile, Sep)`` but yields new Nim ``seq``s.
  var sq = newSeqOfCap[MSlice](n)
  for row in rows(mf, s, sq, n, sep, eat): yield sq

iterator rows*(f: File, s: Sep, row: var seq[string], n=0): seq[string] =
  ## Like ``lines(File)`` but also split each line into columns with ``Sep``.
  for line in lines(f):     #NOTE: This is all that {.push raises: [].} traps
    s.split(line, row, n)
    yield row

iterator rows*(f: File, s: Sep, n=0): seq[string] =
  ## Exactly like ``rows(File, Sep)`` but yields new Nim ``seq``s.
  var sq = newSeqOfCap[string](n)
  for row in rows(f, s, sq, n): yield sq

var doNotUse: MFile
iterator mSlices*(path: string, sep='\n', eat='\r', keep=false,
                  err=stderr, mf: var MFile=doNotUse): MSlice =
  ##A convenient input iterator that ``mopen()``s path or if that fails falls
  ##back to ordinary file IO but constructs ``MSlice`` from lines. ``true keep``
  ##means MFile or strings backing MSlice's are kept alive for life of program
  ##unless you also pass `mf` which returns the `MFile` to close when unneeded.
  let mfl = mopen(path, err=nil)    # MT-safety means cannot just use `mf`
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
      for (cs, n) in f.getDelims(sep):
        if n > 0 and cs[n-1] == sep:                        # `sep` (\n) -> NUL
          cast[ptr UncheckedArray[char]](cs)[n-1] = '\0'
          if eat != '\0' and n > 1 and cs[n-2] == eat:      # `eat` (\r) -> NUL
            cast[ptr UncheckedArray[char]](cs)[n-2] = '\0'
            yield MSlice(mem: cs, len: n - 2)
          else:
            yield MSlice(mem: cs, len: n - 1)
        else:
          yield MSlice(mem: cs, len: n)
      if f!=stdin: f.close() # stdin.close frees fd=0;Could be re-opened&confuse
    except IOError: perror "fopen", err

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

when isMainModule:
  proc testMFile =
    let path = "test.txt"
    var off = 0
    var f = mopen(path, PROT_RW, b=1, allowRemap=true)
    if f.mem == nil: quit "could not create", 1
    for c in "This is data\nin a file\n": f.add c, off
    discard f.resize(off)
    f.close
    try: removeFile path
    except CatchableError: discard
  testMFile()
