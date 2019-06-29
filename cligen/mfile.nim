## Module similar to stdlib memfiles but (at the moment) posix only, and with
## exception-free interface which can help with multi-thread safety inside `||`
## blocks. Also adds a ``noShrink`` safeguard, supports write-only memory, is
## layered differently, has non-system.open-colliding type constructors, and
## uses ``.len`` instead of ``.size`` for constency with other Nim things.

import os, posix, ./osUt, ./mslice # perror cMemCmp mSlices

type
  MFile* = object   ## Like MemFile but safe in an MT-environment
    fd*   : cint    ## open file handle or -1 if not open
    st*   : Stat    ## File metadata at time of open
    prot* : cint    ## Map Protection
    flags*: cint    ## Map Flags (-1 => not open)
    len*  : int     ## Length of file (in bytes) or to unmap
    mem*  : pointer ## First addr to use in [buf0, buf0 + len)

proc mopen*(fd: cint; st: Stat, prot=PROT_READ, flags=MAP_SHARED,
            a=0.Off, b = Off(-1), allowRemap=false, noShrink=false): MFile =
  ## mmap(2) wrapper to simplify life.  Byte range [a,b) of the file pointed to
  ## by 'fd' translates to [result.mem ..< .len).
  var b0 = Off(b)                           #Will be adjusting this, pre-map
  if fd == -1: return
  result.fd    = fd
  result.st    = st
  result.prot  = prot
  result.flags = flags
  if (prot and PROT_WRITE) != 0 and Off(st.st_size) != b:
    if b > Off(st.st_size) or not noShrink:
      if ftruncate(fd, b) == -1:            #Writable & too small => grow
        perror cstring("ftruncate"), 9
        return                              #Likely passed non-writable fd
      discard fstat(fd, result.st)          #Refresh st data ftrunc; Cannot fail
  elif b == Off(-1):                        #Do special whole file mode
    b0 = Off(result.st.st_size)
  b0 = min(b0, Off(result.st.st_size))      #Do not exceed file sz
  if b0 == a: perror cstring("length0slice"), 12; return
  result.mem = mmap(nil, int(b0 - a), prot, flags, fd, Off(a))
  if result.mem == cast[pointer](MAP_FAILED):
    perror cstring("mmap"), 4
    result.mem = nil
    return
  result.len = int(b0 - a)

proc mopen*(fd: cint, prot=PROT_READ, flags=MAP_SHARED,
           a=0, b = -1, allowRemap=false, noShrink=false): MFile =
  ## Init map for already open ``fd``.  See ``mopen(cint,Stat)`` for details.
  if fd == -1:
    return
  if fstat(fd, result.st) == -1:
    perror cstring("fstat"), 5
    return
  if not S_ISREG(result.st.st_mode):  #Even symlns should fstat to ISREG. Quiet
    return                            #error in case client trying /dev/stdin.
  result = mopen(fd, result.st, prot, flags, a, b, allowRemap, noShrink)

proc mopen*(path: string, prot=PROT_READ, flags=MAP_SHARED, a=0, b = -1,
           allowRemap=false, noShrink=false, perMask=0666): MFile =
  ## Init map for ``path``.  ``See mopen(cint,Stat)`` for mapping details.
  ## This proc also creates a file, if necessary, with permission ``perMask``.
  var oflags: cint
  if path.len == 0: return
  if (prot and (PROT_READ or PROT_WRITE)) == (PROT_READ or PROT_WRITE):
    oflags = O_RDWR or O_CREAT
  elif (prot and PROT_READ) != 0:
    oflags = O_RDONLY
  elif (prot and PROT_WRITE) != 0:    #Write-only memory is only rarely useful
    oflags = O_WRONLY or O_CREAT
  let fd = open(path, oflags, perMask)
  if fd == -1:
    perror cstring("open"), 4; return
  result = mopen(fd, prot, flags, a, b, allowRemap, noShrink)
  if not allowRemap:
    if close(fd) == -1: perror cstring("close"), 5
    result.fd = -1

proc close*(mf: var MFile) =
  ## Release memory acquired by MFile mopen()s
  if mf.fd != -1:
    if close(mf.fd) == -1: perror cstring("close"), 5
    mf.fd = -1
  if mf.mem != nil and munmap(mf.mem, mf.len) == -1:
    perror cstring("munmap"), 6
  mf.mem = nil

proc close*(mf: MFile) =
  ## Release memory acquired by MFile mopen()s; Allows let mf = mopen()
  if mf.fd != -1:
    if close(mf.fd) == -1: perror cstring("close"), 5
  if mf.mem != nil and munmap(mf.mem, mf.len) == -1:
    perror cstring("munmap"), 6

proc resize*(mf: var MFile, newFileSize: int): int =
  ## Resize & re-map file underlying an ``allowRemap MFile``. ``.mem`` will
  ## likely change.  **Note**: this assumes entire file is mapped @off=0.
  if mf.fd == -1:
    perror cstring("mopen needs allowRemap"), 22
    return -1
  if ftruncate(mf.fd, newFileSize) == -1:
    perror cstring("ftruncate"), 9
    return -1
  when defined(linux):                          #Maybe NetBSD, too?
    proc mremap(old: pointer; oldSize, newSize: csize; flags: cint): pointer {.
      importc: "mremap", header: "<sys/mman.h>" .}
    let newAddr = mremap(mf.mem, csize(mf.len), csize(newFileSize), cint(1))
    if newAddr == cast[pointer](MAP_FAILED):
      perror cstring("mremap"), 6
      return -1
  else: #On Linux mremap can be over 100X faster than this munmap+mmap cycle.
    if munmap(mf.mem, mf.len) != 0:
      perror cstring("munmap"), 6
      return -1
    let newAddr = mmap(nil, newFileSize, mf.prot, mf.flags, mf.fd, 0)
    if newAddr == cast[pointer](MAP_FAILED):
      perror cstring("mmap"), 4
      return -1
  mf.mem = newAddr
  mf.len = newFileSize

proc `<`*(a,b: MFile): bool = cMemCmp(a.mem, b.mem, min(a.len, b.len)) < 0

proc `==`*(a,b: MFile): bool = a.len==b.len and cMemCmp(a.mem,b.mem,a.len)==0

proc `==`*(a: MFile, p: pointer): bool = a.mem==p

proc toMSlice*(mf: MFile): MSlice =  #I'd prefer to call this MSlice, but if I
  result.mem = mf.mem                #do, import'rs of [mfile,mslice] must
  result.len = mf.len                #qualify MSlice,but only in generic param.

iterator mSlices*(mf: MFile, sep='\l', eat='\r'): MSlice {.inline.} =
  for ms in mSlices(mf.toMSlice, sep, eat):
    yield ms

iterator lines*(mf:MFile, buf:var string, sep='\l', eat='\r'):string {.inline.}=
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

iterator lines*(mf: MFile, sep='\l', eat='\r'): string {.inline.} =
  ## Exactly like ``lines(MFile, var string)`` but yields new Nim strings.
  ##
  ## .. code-block:: nim
  ##   for line in lines(mopen("foo")): echo line   #Example
  var buf = newStringOfCap(80)
  for line in lines(mf, buf, sep, eat): yield buf

iterator rows*(mf: MFile, s: Splitr, row: var seq[MSlice],
               n=0, sep='\l', eat='\r'): seq[MSlice] {.inline.} =
  ##Like ``lines(MFile)`` but also split each line into columns with ``Splitr``.
  if mf.mem != nil:
    for line in mSlices(mf, sep, eat):
      s.split(line, row, n)
      yield row

iterator rows*(mf: MFile, s: Splitr, n=0, sep='\l', eat='\r'): seq[MSlice] {.inline.} =
  ## Exactly like ``rows(MFile, Splitr)`` but yields new Nim ``seq``s.
  var sq = newSeqOfCap[MSlice](n)
  for row in rows(mf, s, sq, n, sep, eat): yield sq

iterator rows*(f: File, s: Splitr, row: var seq[string], n=0): seq[string] {.inline.}=
  ## Like ``lines(File)`` but also split each line into columns with ``Splitr``.
  for line in lines(f):
    s.split(line, row, n)
    yield row

iterator rows*(f: File, s: Splitr, n=0): seq[string] {.inline.} =
  ## Exactly like ``rows(File, Splitr)`` but yields new Nim ``seq``s.
  var sq = newSeqOfCap[string](n)
  for row in rows(f, s, sq, n): yield sq

iterator mSlices*(path:string, sep='\l', eat='\r', keep=false):MSlice{.inline.}=
  ##A convenient input iterator that ``mopen()``s path or if that fails falls
  ##back to ordinary file IO but constructs ``MSlice`` from lines. ``true keep``
  ##means MFile or strings backing MSlice's are kept alive for life of program.
  let mf = mopen(path)
  if mf.mem != nil:
    for ms in mSlices(mf.toMSlice, sep, eat):
      yield ms
    if not keep: mf.close()
  else:
    let f = open(path)
    for s in lines(f):
      if keep:
        var scpy = $s
        GC_ref(scpy)
        yield toMSlice(scpy)
      else:
        yield toMSlice(s)
    f.close()
