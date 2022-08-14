import std/[heapqueue, posix], cligen, cligen/[osUt, posixUt, dents, statx]

type TimePath = tuple[tm: int64, path: string]

proc timeStamp(st: Statx, tim: char, dir: int): int64 {.inline.} =
  case tim
  of 'b': dir * getBirthTimeNsec(st)
  of 'a': dir * getLastAccTimeNsec(st)
  of 'm': dir * getLastModTimeNsec(st)
  of 'c': dir * getCreationTimeNsec(st)
  of 'v': dir * max(getLastModTimeNsec(st), getCreationTimeNsec(st))
  else: 0

proc doStat(dfd: cint, path: string; nmAt: int, st: var Statx; Deref,
            quiet: bool): bool {.inline.} =
  if Deref:     # lstat if no deref requested or as fallback if stat fails.
    if statxat(dfd, path[nmAt..^1].cstring, st, 0) == 0: return true
    if lstatxat(dfd, path[nmAt..^1].cstring, st, 0) == 0: return true
  elif lstatxat(dfd, path[nmAt..^1].cstring, st, 0) == 0: return true
  if not quiet: stderr.write "newest: \"", path, "\" ", strerror(errno), '\n'

proc printNewest*(n=1, time="m", recurse=1, chase=false, Deref=false,
                  kinds={fkFile}, quiet=false, xdev=false, outEnd="\n",
                  file="", delim='\n', eof0=false, paths: seq[string]) =
  ## Echo ended by *outEnd* <= *n* newest files in file *time* order
  ## `{-}[bamcv]` for Birth, Access, Mod, Ctime, Version=max(MC); { `-` | CAPITAL
  ## means ***oldest*** }.  Examined files = UNION of *paths* + optional
  ## *delim*-delimited input *file* ( ``stdin`` if `"-"`|if `""` & ``stdin`` is
  ## not a terminal ), **maybe recursed** as roots.  E.g. to echo the 3 oldest
  ## regular files by m-time under the CWD:
  ##   ``find . -type f -print | newest -n3 -t-m``.
  let err = if quiet: nil else: stderr
  let tO = fileTimeParse(time)                  #- or CAPITAL=oldest
  let it = both(paths, fileStrings(file, delim))
  var q  = initHeapQueue[TimePath]()            # min-heap with q[0]=min
  for root in it():
    if root.len == 0: continue                  # skip any improper inputs
    forPath(root, recurse, false, chase, xdev, eof0, err,
            depth, path, nmAt, ino, dt, lst, dfd, dst, did):
      if dt != DT_UNKNOWN:                      # unknown here => disappeared
        if (dt==DT_LNK and Deref and doStat(dfd,path,nmAt,lst,Deref,quiet)) or
           lst.stx_nlink != 0 or doStat(dfd,path,nmAt,lst,Deref,quiet):
          if lst.stx_mode.match(kinds):
            let tp = (timeStamp(lst, tO.tim, tO.dir), path)
            if q.len < n  : q.push(tp)
            elif tp > q[0]: discard q.replace(tp)
    do: discard
    do: discard
    do: recFailDefault("newest", path)
  while q.len > 0:                              # q now has top n times; Print
    stdout.write q.pop().path, outEnd           #..in the specified-time order.

when isMainModule:  # Exercise this with an actually useful CLI wrapper.
  dispatch printNewest,
           help = { "n"      : "number of 'newest' files",
                    "time"   : "timestamp to compare ({-}[bamcv]\\*)",
                    "recurse": "recurse n-levels on dirs; 0:unlimited",
                    "chase"  : "chase symlinks to dirs in recursion",
                    "xdev"   : "block recursion across device boundaries",
                    "Deref"  : "dereference symlinks for file times",
                    "kinds"  : "i-node type like find(1): [fdlbcps]",
                    "quiet"  : "suppress file access errors",
                    "outEnd" : "output record terminator",
                    "file"   : "optional input (\"-\"|!tty=stdin)",
                    "delim"  : "input file record delimiter" }
