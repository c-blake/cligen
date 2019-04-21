import posix, strutils

proc ns*(t: Timespec): int =
  ## Signed ns since epoch; Signed 64bit ints => +-292 years from 1970.
  int(t.tv_sec) * 1000_000_000 + t.tv_nsec

proc fileTimeParse*(code: string): tuple[tim: char, dir: int] =
  ## Parse [+-][amcvAMCV]* into a file time order specification.  In case
  ## default increasing order is non-intuitive, this provides two ways to
  ## specify reverse order: prepend with '-' or flip letter casing.
  if code.len < 1:
    result.dir = +1
    result.tim = 'm'
    return
  result.dir = if code[0] == '-': -1 else: +1
  result.tim  = if code[0] in { '-', '+' }: code[1] else: code[0]
  if result.tim == toUpperAscii(result.tim):
    result.dir = -result.dir
    result.tim  = toLowerAscii(result.tim)

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
