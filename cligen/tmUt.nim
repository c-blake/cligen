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
