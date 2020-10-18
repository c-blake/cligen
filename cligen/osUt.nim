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

import std/[os, terminal, strutils, dynlib, times, stats, math]
type csize = uint

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

proc c_getdelim*(p: ptr cstring, nA: ptr csize, dlm: cint, stream: File): int {.
  importc: "getdelim", header: "<stdio.h>".}

iterator getDelim*(stream: File, dlm: char='\n'): string =
  ## Efficient file line/record iterator using POSIX getdelim
  proc free(pointr: cstring) {.importc: "free", header: "<stdlib.h>".}
  var cline: cstring
  var nAlloc: csize
  var res: string
  while true:
    let length = c_getdelim(cline.addr, nAlloc.addr, cint(dlm), stream)
    if length == -1: break
    res.setLen(length - 1)      #-1 => remove dlm char like system.lines()
    if length > 1:
      copyMem(addr res[0], cline, length - 1)
    yield res
  free(cline)

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
  when defined(linux) and not defined(android):
    proc c_fwrite(buf: pointer, size, n: csize, f: File): cint {.
            importc: "fwrite_unlocked", header: "<stdio.h>".}
  else:
    proc c_fwrite(buf: pointer, size, n: csize, f: File): cint {.
            importc: "fwrite", header: "<stdio.h>".}
  result = c_fwrite(buffer, 1, len.csize, f)

#when defined(nimHasExceptionsQuery):
#  const gotoBasedExceptions* = compileOption("exceptions", "goto")
#else:
#  const gotoBasedExceptions* = false

proc urite*(f: File, s: string) {.inline.} =
# when gotoBasedExceptions:
#   if uriteBuffer(f, cstring(s), s.len) != s.len:
#     raise newException(IOError, "cannot write string to file")
  discard uriteBuffer(f, cstring(s), s.len)

proc urite*(f: File, a: varargs[string, `$`]) {.inline.} =
  ## Unlocked (i.e. single threaded) libc write (maybe Linux-only).
  for x in items(a): urite(f, x)

proc cfeof(f: File): cint {.importc: "feof", header: "<stdio.h>".}
proc eof*(f: File): bool {.inline.} = f.cfeof != 0

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
  let sym = symAddr(lib, cols[1])
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
