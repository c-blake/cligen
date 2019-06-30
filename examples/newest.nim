import posix, heapqueue, cligen/[osUt, posixUt, statx], cligen

proc timeStamp(st: Statx, tim: char, dir: int): int =
  case tim
  of 'b': dir * getBirthTimeNsec(st)
  of 'a': dir * getLastAccTimeNsec(st)
  of 'm': dir * getLastModTimeNsec(st)
  of 'c': dir * getCreationTimeNsec(st)
  of 'v': dir * max(getLastModTimeNsec(st), getCreationTimeNsec(st))
  else: 0

proc doStat(path: string; st: var Statx; Deref, quiet: bool): bool =
  if Deref:
    if stat(path, st) == 0: return true
    if lstat(path, st) == 0: return true     # lstat fallback if stat fails..
  elif lstat(path, st) == 0: return true     #..or if re no deref requested.
  if not quiet:
    stderr.write("newest: \"", path, "\" missing\n")

type StrGen* = iterator(): string             ## A string generator iterator
type TimePath = tuple[tm: int, path: string]

iterator timePaths(paths: StrGen; time: string; Deref,quiet: bool): TimePath =
  let tO = fileTimeParse(time)                #- or CAP=oldest
  var st: Statx
  for path in paths():
    if not doStat(path, st, Deref, quiet):
      continue
    yield (timeStamp(st, tO.tim, tO.dir), path)

iterator newest*(paths:StrGen, n=1, time="m", Deref=false, quiet=false):string =
  ## Yield at most ``n`` newest files in ``time``-order where ``time`` can be
  ## [-][BAMCV]* for Birth, Access, Mod, Ctime, Version=max(M,C); Optional "-"
  ## means oldest not newest.  Eg., quietly print oldest-by-mtime 2 DIR entries:
  ##
  ## .. code-block ::
  ##   iterator gen(): string =
  ##     for e in os.walkDir(DIR, false): yield e.path
  ##   for e in newest(gen, 2, "-m"): echo e
  var hq = newHeapQueue[TimePath]()         # min-heap with hq[0]=min
  for tp in timePaths(paths, time, Deref, quiet):
    if hq.len < n  : hq.push(tp)            # build initial heap
    elif tp > hq[0]: discard hq.replace(tp) # time > curr min => replace
  while hq.len > 0:                         # hq now has top n times.
    let e = hq.pop()                        # pop min elt will yield in..
    yield e.path                            #..the specified-time order.

proc printNewest*(n=1, time="m", Deref=false, quiet=false, outEnd="\n",
                  file="", delim='\n', paths: seq[string]) =
  ## Print ``<=n`` newest paths ended by ``outEnd`` in ``time``-order {
  ## [-][bamcv].* for Birth, Access, Mod, Ctime, Version=max(MC); optional '-'
  ## means oldest instead of newest }.  Examined paths are UNION of ``paths`` +
  ## optional ``delim``-delimited input ``file`` (stdin if "-"|if "" & stdin is
  ## not a tty).  Eg., ``find -type f|newest -t-m`` prints the m-oldest file.
  for e in newest(both(paths, fileStrings(file, delim)), n, time, Deref, quiet):
    stdout.write e, outEnd

when isMainModule:  # Exercise this with an actually useful CLI wrapper.
  dispatch(printNewest, cmdName="newest",
           help = { "n"     : "number of 'newest' files",
                    "time"  : "timestamp to compare ([-][bamcv].*)",
                    "Deref" : "dereference symlinks for file times",
                    "quiet" : "suppress file access errors",
                    "outEnd": "output record terminator",
                    "file"  : "optional input (\"-\"|!tty=stdin)",
                    "delim" : "input file record delimiter" })
