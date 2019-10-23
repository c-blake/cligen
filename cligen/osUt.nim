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

import os, terminal, strutils #, sets, tables, strformat, ./sysUt #`:=`
type csize = uint

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
  result = c_fwrite(buffer, 1, len.csize, f)

proc urite*(f: File, s: string) =
  if uriteBuffer(f, cstring(s), s.len) != s.len:
    raise newException(IOError, "cannot write string to file")

proc urite*(f: File, a: varargs[string, `$`]) =
  for x in items(a): urite(f, x)

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
