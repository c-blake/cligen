## The idea of this module is to allow callers to pretend their system has the
## Linux ``statx`` call & ``Statx`` type even if it does not.  Callers simply
## program to the "superset" using ``Statx`` and ``statx`` and i just works.
## We simulate/translate ordinary ``Stat`` results when necessary.

import std/posix, cligen/posixUt

const haveStatx* = (gorgeEx "[ -e /usr/include/bits/statx.h ]")[1] == 0
{.passC: "-D_GNU_SOURCE".}
when not haveStatx:
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

proc `<`*(x, y: StatxTs): bool {.inline.} =
  x.tv_sec < y.tv_sec or (x.tv_sec == y.tv_sec and x.tv_nsec < y.tv_sec)

proc `<=`*(x, y: StatxTs): bool {.inline.} =
  x.tv_sec < y.tv_sec or (x.tv_sec == y.tv_sec and x.tv_nsec <= y.tv_sec)

proc toInt64*(t: StatxTs): int64 {.inline.} =
  ## 64-bits represents +-292 years from 1970 exactly & conveniently.
  t.tv_sec * 1_000_000_000 + t.tv_nsec

proc toStatxTs*(t: int64): StatxTs {.inline.} =
  result.tv_sec  = t div 1_000_000_000
  result.tv_nsec = int32(t - result.tv_sec * 1_000_000_000)

export impConst, impCint, AT_FDCWD, AT_SYMLINK_NOFOLLOW, AT_SYMLINK_FOLLOW,
       AT_REMOVEDIR, AT_EACCESS      ## These & next export used to live here.
when defined(linux) and haveStatx:
  export AT_NO_AUTOMOUNT, AT_EMPTY_PATH
  impCint("fcntl.h", AT_STATX_SYNC_TYPE)
  impCint("fcntl.h", AT_STATX_SYNC_AS_STAT)
  impCint("fcntl.h", AT_STATX_FORCE_SYNC)
  impCint("fcntl.h", AT_STATX_DONT_SYNC)
when haveStatx:
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

when haveStatx:
  var statxFlags* = AT_STATX_DONT_SYNC
  var statxMask* = STATX_ALL

  proc statx*(dirfd: cint, path: cstring, flags: cint, mask: cint,
              stx: ptr Statx): cint {.importc: "statx", header: "<sys/stat.h>".}

  proc statx*(dirfd: cint, path: cstring, stx: var Statx, flags: cint,
              mask=statxMask): cint {.inline.} =
    ##A statx that looks more like ``fstatat`` with an ignorable final parameter
    statx(dirfd, path, flags, mask, stx.addr)

  proc statx*(path: cstring, stx: var Statx,
              flags=statxFlags, mask=statxMask): cint {.inline.} =
    ##A Linux statx wrapper with a call signature more like regular ``stat``.
    statx(AT_FDCWD, path, flags, mask, stx.addr)

  proc lstatx*(path: cstring, stx: var Statx,
              flags=(statxFlags or AT_SYMLINK_NOFOLLOW), mask=statxMask): cint {.inline.} =
    ##A Linux statx wrapper with a call signature more like regular ``lstat``.
    statx(AT_FDCWD, path, flags, mask, stx.addr)

  proc fstatx*(fd: cint, stx: var Statx,
              flags=(AT_EMPTY_PATH or statxFlags), mask=statxMask): cint {.inline.} =
    ##A Linux statx wrapper with a call signature more like regular ``fstat``.
    statx(fd, "", flags, mask, stx.addr)
else:
  var statxMask* = cint(0) # Just a dummy to compile when not haveStatx

#A code porting/compatibility layer so client code can just replace "Stat" with
#"Statx", use all the same query call names as overloads, and access all .st_
#fields that do best effort emulation of their .stx_ counterparts.

#This just uses the antiquated high/low byte of a 16-bit int.  It would be best
#to get major() & minor() macros out of sys/types.h | sys/sysmacros.h.
proc st_major*(dno: Dev): uint32 {.inline.} = (dno.uint shr 8).uint32
proc st_minor*(dno: Dev): uint32 {.inline.} = (dno.uint and 0xFF).uint32

proc toTimespec*(ts: StatxTs): Timespec {.inline.} =
  result.tv_sec = ts.tv_sec.Time
  result.tv_nsec = ts.tv_nsec

proc toStatxTs*(ts: Timespec): StatxTs {.inline.} =
  result.tv_sec = ts.tv_sec.int64
  result.tv_nsec = ts.tv_nsec.int32

proc stat2statx(dst: var Statx, src: Stat) {.inline.} =
  dst.stx_mask            = 0xFFFFFFFF.uint32
# dst.stx_attributes      = .uint64     #No analogues; Extra syscalls?
# dst.stx_attributes_mask = .uint64
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

proc st_blksize*(st: Statx): Blksize {.inline.} = st.stx_blksize.Blksize
proc st_nlink*(st: Statx): Nlink     {.inline.} = st.stx_nlink.Nlink
proc st_uid*(st: Statx): Uid         {.inline.} = st.stx_uid.Uid
proc st_gid*(st: Statx): Gid         {.inline.} = st.stx_gid.Gid
proc st_mode*(st: Statx): Mode       {.inline.} = st.stx_mode.Mode
proc st_ino*(st: Statx): Ino         {.inline.} = st.stx_ino.Ino
proc st_size*(st: Statx): Off        {.inline.} = st.stx_size.Off
proc st_blocks*(st: Statx): Blkcnt   {.inline.} = st.stx_blocks.Blkcnt
proc st_atim*(st: Statx): Timespec   {.inline.} = st.stx_atime.toTimespec
proc st_ctim*(st: Statx): Timespec   {.inline.} = st.stx_ctime.toTimespec
proc st_mtim*(st: Statx): Timespec   {.inline.} = st.stx_mtime.toTimespec
proc st_rmaj*(st: Statx): Dev        {.inline.} = st.stx_rdev_major.Dev
proc st_rmin*(st: Statx): Dev        {.inline.} = st.stx_rdev_minor.Dev
proc st_dev*(st: Statx): Dev         {.inline.} =
  (st.stx_dev_major shl 32 or st.stx_dev_minor).Dev
proc `st_nlink=`*(st: var Statx, n: Nlink) {.inline.} = st.stx_nlink = uint32(n)

proc st_btim*(st: Statx): Timespec {.inline.} = st.stx_btime.toTimespec

proc st_vtim*(st: Statx): Timespec {.inline.} =
  if cmp(st.st_mtim, st.st_ctim) > 0: st.st_mtim
  else:                               st.st_ctim

proc stat*(path: cstring, stx: var Statx): cint {.inline.} =
  when haveStatx:
    result = statx(path, stx)
  else:
    var st: Stat
    result = stat(path, st)
    stat2statx(stx, st)

proc lstat*(path: cstring, stx: var Statx): cint {.inline.} =
  when haveStatx:
    result = lstatx(path, stx)
  else:
    var st: Stat
    result = lstat(path, st)
    stat2statx(stx, st)

proc fstat*(fd: cint, stx: var Statx): cint {.inline.} =
  when haveStatx:
    result = fstatx(fd, stx)
  else:
    var st: Stat
    result = fstat(fd, st)
    stat2statx(stx, st)

proc fstatat*(dirfd: cint, path: cstring, stx: var Statx, flags: cint):
       cint {.inline.} =
  ## Always ``fstatat`` but take/return ``Statx`` w/simulated e.g. stx_btime.
  var st: Stat
  result = fstatat(dirfd, path, st, flags)
  stat2statx(stx, st)

proc statx*(dirfd: cint, path: cstring, flags: cint, stx: var Statx,
            mask=statxMask): cint {.inline.} =
  ## A ``statx`` that looks more like ``fstatat`` w/a final parameter ignored
  ## when simulated.
  when haveStatx:
    result = statx(dirfd, path, flags, statxMask, stx.addr)
  else:
    fstatat(dirfd, path, stx, flags)

proc statxat*(dirfd: cint, path: cstring, stx: var Statx, flags: cint): cint {.inline.} =
  statx(dirfd, path, flags, stx)

proc lstatxat*(dirfd: cint, path: cstring, stx: var Statx, flags: cint): cint {.inline.} =
  statx(dirfd, path, flags or AT_SYMLINK_NOFOLLOW, stx)

template makeGetTimeNSec(name: untyped, field: untyped) =
  proc name*(stx: Statx): int64 {.inline.} =
    int(stx.field.tv_sec)*1_000_000_000 + stx.field.tv_nsec
makeGetTimeNSec(getLastAccTimeNsec, stx_atime)
makeGetTimeNSec(getLastModTimeNsec, stx_mtime)
makeGetTimeNSec(getCreationTimeNsec, stx_ctime)
makeGetTimeNSec(getBirthTimeNsec, stx_btime)

proc getBirthTimeNsec*(path: string): int64 =
  var stx: Statx
  result = if stat(path, stx) < cint(0): 0'i64 else: getBirthTimeNsec(stx)
