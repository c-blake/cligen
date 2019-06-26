import posix

{.passC: "-D_GNU_SOURCE".}
when defined(haveNoStatx):
  type
    StatxTs* {.final, pure.} = object
      tv_sec*: int64
      tv_nsec*: int32

    Statx* {.final, pure.} = object ## struct statx
      stx_mask*:            uint32   ## Mask of bits indicating filled fields
      stx_blksize*:         uint32   ## Block size for filesystem I/O
      stx_attributes*:      uint64   ## Extra file attribute indicators
      stx_nlink*:           uint32   ## Number of hard links
      stx_uid*:             uint32   ## User ID of owner
      stx_gid*:             uint32   ## Group ID of owner
      stx_mode*:            uint16   ## File type and mode
      stx_ino*:             uint64   ## Inode number
      stx_size*:            uint64   ## Total size in bytes
      stx_blocks*:          uint64   ## Number of 512B blocks allocated
      stx_attributes_mask*: uint64   ## Mask showing what stx_attributes supports
      stx_atime*:           StatxTs  ## Last access
      stx_btime*:           StatxTs  ## Birth/Creation
      stx_ctime*:           StatxTs  ## Last status change
      stx_mtime*:           StatxTs  ## Last modification
      stx_rdev_major*:      uint32   ## Major ID if file is a device
      stx_rdev_minor*:      uint32   ## Minor ID if file is a device
      stx_dev_major*:       uint32   ## Major ID of dev of FS where file resides
      stx_dev_minor*:       uint32   ## Minor ID of dev of FS where file resides
else:
  type
    StatxTs* {.importc: "struct statx_timestamp",
               header: "<sys/stat.h>", final, pure.} = object
      tv_sec*: int64
      tv_nsec*: int32
      statx_timestamp_pad1: int32

    Statx* {.importc: "struct statx",
             header: "<sys/stat.h>", final, pure.} = object ## struct statx
      stx_mask*:            uint32   ## Mask of bits indicating filled fields
      stx_blksize*:         uint32   ## Block size for filesystem I/O
      stx_attributes*:      uint64   ## Extra file attribute indicators
      stx_nlink*:           uint32   ## Number of hard links
      stx_uid*:             uint32   ## User ID of owner
      stx_gid*:             uint32   ## Group ID of owner
      stx_mode*:            uint16   ## File type and mode
      stx_ino*:             uint64   ## Inode number
      stx_size*:            uint64   ## Total size in bytes
      stx_blocks*:          uint64   ## Number of 512B blocks allocated
      stx_attributes_mask*: uint64   ## Mask showing what stx_attributes supports
      stx_atime*:           StatxTs  ## Last access
      stx_btime*:           StatxTs  ## Birth/Creation
      stx_ctime*:           StatxTs  ## Last status change
      stx_mtime*:           StatxTs  ## Last modification
      stx_rdev_major*:      uint32   ## Major ID if file is a device
      stx_rdev_minor*:      uint32   ## Minor ID if file is a device
      stx_dev_major*:       uint32   ## Major ID of dev of FS where file resides
      stx_dev_minor*:       uint32   ## Minor ID of dev of FS where file resides

template impConst*(T: untyped, path: string, name: untyped): untyped {.dirty.} =
  var `loc name` {.header: path, importc: astToStr(name) .}: `T`
  let name* {.inject.} = `loc name`

template impCint*(path: string, name: untyped): untyped {.dirty.} =
  impConst(cint, path, name)

impCint("fcntl.h", AT_FDCWD)            ## Tells *at calls to use CurrWkgDir
impCint("fcntl.h", AT_SYMLINK_NOFOLLOW) ## Do not follow symbolic links
impCint("fcntl.h", AT_REMOVEDIR)        ## Remove dir instead of unlinking file
impCint("fcntl.h", AT_SYMLINK_FOLLOW)   ## Follow symbolic links
impCint("fcntl.h", AT_EACCESS)          ## Test access perm for EID,not real ID
when defined(linux) and not defined(haveNoStatx):
  impCint("fcntl.h", AT_NO_AUTOMOUNT)   ## Suppress terminal automount traversal
  impCint("fcntl.h", AT_EMPTY_PATH)     ## Allow empty relative pathname
  impCint("fcntl.h", AT_STATX_SYNC_TYPE)
  impCint("fcntl.h", AT_STATX_SYNC_AS_STAT)
  impCint("fcntl.h", AT_STATX_FORCE_SYNC)
  impCint("fcntl.h", AT_STATX_DONT_SYNC)
when not defined(haveNoStatx):
  impCint("sys/stat.h", STATX_TYPE)
  impCint("sys/stat.h", STATX_MODE)
  impCint("sys/stat.h", STATX_NLINK)
  impCint("sys/stat.h", STATX_UID)
  impCint("sys/stat.h", STATX_GID)
  impCint("sys/stat.h", STATX_ATIME)
  impCint("sys/stat.h", STATX_MTIME)
  impCint("sys/stat.h", STATX_CTIME)
  impCint("sys/stat.h", STATX_INO)
  impCint("sys/stat.h", STATX_SIZE)
  impCint("sys/stat.h", STATX_BLOCKS)
  impCint("sys/stat.h", STATX_BASIC_STATS)
  impCint("sys/stat.h", STATX_ALL)
  impCint("sys/stat.h", STATX_BTIME)
  impCint("sys/stat.h", STATX_ATTR_COMPRESSED)
  impCint("sys/stat.h", STATX_ATTR_IMMUTABLE)
  impCint("sys/stat.h", STATX_ATTR_APPEND)
  impCint("sys/stat.h", STATX_ATTR_NODUMP)
  impCint("sys/stat.h", STATX_ATTR_ENCRYPTED)
  impCint("sys/stat.h", STATX_ATTR_AUTOMOUNT)

when not defined(haveNoStatx):
  var statxFlags* = AT_STATX_DONT_SYNC
  var statxMask* = STATX_ALL

  proc statx*(dirfd: cint, path: cstring, flags: cint, mask: cint,
              stx: ptr Statx): cint {.importc: "statx", header: "<sys/stat.h>".}

  proc statx*(path: cstring, stx: var Statx,
              flags=statxFlags, mask=statxMask): cint =
    ##A Linux statx wrapper with a call signature more like regular ``stat``.
    statx(AT_FDCWD, path, flags, mask, stx.addr)

  proc lstatx*(path: cstring, stx: var Statx,
              flags=(statxFlags or AT_SYMLINK_NOFOLLOW), mask=statxMask): cint =
    ##A Linux statx wrapper with a call signature more like regular ``lstat``.
    statx(AT_FDCWD, path, flags, mask, stx.addr)

  proc fstatx*(fd: cint, stx: var Statx,
              flags=(AT_EMPTY_PATH or statxFlags), mask=statxMask): cint =
    ##A Linux statx wrapper with a call signature more like regular ``fstat``.
    statx(fd, "", flags, mask, stx.addr)

#A code porting/compatibility layer so client code can just replace "Stat" with
#"Statx", use all the same query call names as overloads, and access all .st_
#fields that do best effort emulation of their .stx_ counterparts.

#This just uses the antiquated high/low byte of a 16-bit int.  It would be best
#to get major() & minor() macros out of sys/types.h | sys/sysmacros.h.
proc st_major*(dno: Dev): uint32 = (dno.uint shr 8).uint32
proc st_minor*(dno: Dev): uint32 = (dno.uint and 0xFF).uint32

proc toTimespec*(ts: StatxTs): Timespec =
  result.tv_sec = ts.tv_sec.Time
  result.tv_nsec = ts.tv_nsec

proc cmp*(a, b: Timespec): int =
  let s = cmp(a.tv_sec.uint, b.tv_sec.uint)
  if s != 0: return s
  return cmp(a.tv_nsec, b.tv_nsec)

proc `<=`*(a, b: Timespec): bool = cmp(a, b) <= 0

proc `-`*(a, b: Timespec): int =
  result = (a.tv_sec.int - b.tv_sec.int) * 1_000_000_000 +
           (a.tv_nsec.int - b.tv_nsec.int)

proc toStatxTs*(ts: Timespec): StatxTs =
  result.tv_sec = ts.tv_sec.int64
  result.tv_nsec = ts.tv_nsec.int32

when defined(haveNoStatx):
  proc stat2statx(dst: var Statx, src: Stat) =
    dst.stx_mask            = 0xFFFFFFFF.uint32
#   dst.stx_attributes      = .uint64     #No analogues; Extra syscalls?
#   dst.stx_attributes_mask = .uint64
    dst.stx_blksize         = src.st_blksize.uint32
    dst.stx_nlink           = src.st_nlink.uint32
    dst.stx_uid             = src.st_uid.uint32
    dst.stx_gid             = src.st_gid.uint32
    dst.stx_mode            = src.st_mode.uint16
    dst.stx_ino             = src.st_ino.uint64
    dst.stx_size            = src.st_size.uint64
    dst.stx_blocks          = src.st_blocks.uint64
    dst.stx_atime           = src.st_atim.toStatxTs
    dst.stx_btime = min(src.st_atim, min(src.st_ctim, src.st_mtim)).toStatxTs
    dst.stx_ctime           = src.st_ctim.toStatxTs
    dst.stx_mtime           = src.st_mtim.toStatxTs
    dst.stx_rdev_major      = src.st_rdev.st_major.uint32
    dst.stx_rdev_minor      = src.st_rdev.st_minor.uint32
    dst.stx_dev_major       = src.st_dev.st_major.uint32
    dst.stx_dev_minor       = src.st_dev.st_minor.uint32

proc st_blksize*(st: Statx): Blksize = st.stx_blksize.Blksize
proc st_nlink*(st: Statx): Nlink     = st.stx_nlink.Nlink
proc st_uid*(st: Statx): Uid         = st.stx_uid.Uid
proc st_gid*(st: Statx): Gid         = st.stx_gid.Gid
proc st_mode*(st: Statx): Mode       = st.stx_mode.Mode
proc st_ino*(st: Statx): Ino         = st.stx_ino.Ino
proc st_size*(st: Statx): Off        = st.stx_size.Off
proc st_blocks*(st: Statx): Blkcnt   = st.stx_blocks.Blkcnt
proc st_atim*(st: Statx): Timespec   = st.stx_atime.toTimespec
proc st_ctim*(st: Statx): Timespec   = st.stx_ctime.toTimespec
proc st_mtim*(st: Statx): Timespec   = st.stx_mtime.toTimespec
proc st_rmaj*(st: Statx): Dev        = st.stx_rdev_major.Dev
proc st_rmin*(st: Statx): Dev        = st.stx_rdev_minor.Dev
proc st_dev*(st: Statx): Dev         = st.stx_dev_minor.Dev

proc st_btim*(st: Statx): Timespec = st.stx_btime.toTimespec

proc st_vtim*(st: Statx): Timespec =
  if cmp(st.st_mtim, st.st_ctim) > 0: st.st_mtim
  else:                               st.st_ctim

proc stat*(path: cstring, stx: var Statx): cint {.inline.} =
  when defined(haveNoStatx):
    var st: Stat
    result = stat(path, st)
    stat2statx(stx, st)
  else:
    result = statx(path, stx)

proc lstat*(path: cstring, stx: var Statx): cint {.inline.} =
  when defined(haveNoStatx):
    var st: Stat
    result = lstat(path, st)
    stat2statx(stx, st)
  else:
    result = lstatx(path, stx)

proc fstat*(fd: cint, stx: var Statx): cint {.inline.} =
  when defined(haveNoStatx):
    var st: Stat
    result = fstat(fd, st)
    stat2statx(stx, st)
  else:
    result = fstatx(fd, stx)

template makeGetTimeNSec(name: untyped, field: untyped) =
  proc name*(stx: Statx): int =
    int(stx.field.tv_sec)*1_000_000_000 + stx.field.tv_nsec
makeGetTimeNSec(getLastAccTimeNsec, stx_atime)
makeGetTimeNSec(getLastModTimeNsec, stx_mtime)
makeGetTimeNSec(getCreationTimeNsec, stx_ctime)
makeGetTimeNSec(getBirthTimeNsec, stx_btime)

proc getBirthTimeNsec*(path: string): int =
  var stx: Statx
  result = if stat(path, stx) < cint(0): 0 else: getBirthTimeNsec(stx)
