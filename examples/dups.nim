import os, posix, strutils, sets, tables, hashes, std/sha1, algorithm,
  cligen, cligen/[mfile,fileUt,strUt, osUt,posixUt,sysUt] #fileEq,parseSlice..

type Lg* = enum osErr, summ                     #A tiny logging system
var dupsLog* = { osErr }
proc perr*(x: varargs[string, `$`]) =           #OS Errors like permissions
  if osErr in dupsLog: stderr.write "dups: "; stderr.write x; stderr.write ": ",
                                    osErrorMsg(osLastError()), "\n"

proc getMeta(paths: (iterator():string), Deref=false, mL=1):
       Table[int, seq[string]] =
  result = initTable[int, seq[string]](512)
  var st: Stat
  var inodes = initHashSet[int](512)
  for path in paths():
    if Deref:                                   #stat|lstat based on Deref
      if stat(path, st) != 0: perr "stat ", path
    else:
      if lstat(path, st) != 0: perr "lstat ", path
    if not S_ISREG(st.st_mode):                 #Only meaningful to compare..
      continue                                  #..S_ISREG=regular & symlinks.
    if st.st_size < mL:                         #One easy way to exclude len0.
      continue                                  #Other small mins also useful.
    if inodes.containsOrIncl(int(st.st_ino)):   #Only keep 1st discovered path
      continue                                  #..for any given inode.
    result.mgetOrPut(st.st_size, @[]).add(path)

proc justPaths(x: openArray[tuple[m: MFile, path: string]]): seq[string] =
  result.setLen(x.len)                          #extract paths from tuples
  for i in 0 ..< x.len: result[i] = x[i].path   #(iterators cannot scope procs)

iterator carefulSplit*(paths: seq[string]): seq[string] =
  ## Split a set of same hash (maybe just size) paths into >=1 set(s) via sort.
  if paths.len <= 2:                        #Common doubles case w/simple answer
    if fileEq(paths[0], paths[1]): yield paths  #inlining triples does not help
  elif paths.len < 4000:                    #OS limit on simult. mmaps
    var files = newSeq[tuple[m: MFile, path: string]](paths.len)
    for i in 0 ..< files.len:
      files[i].m = mopen(paths[i])
      if files[i].m.mem == nil:
        perr "comparing ", paths[i]
        files[i].path = ""
      else:
        files[i].path = paths[i]
    files.sort() #NOTE Custom radix sort may help worst case on giant dup sets
    var a = 0
    for b in 1 ..< files.len:                         #for each file
      if files[b].m != files[a].m:                      #file != anchor
        if b - a > 1: yield justPaths(files[a ..< b])   #Yield if 2|more
        a = b                                           #Reset anchor always
    if files.len - a > 1: yield justPaths(files[a ..< files.len])
    for i in 0 ..< files.len:                         #close all files
      if files[i].path.len > 0: files[i].m.close()
  else:                                         #Too big to sort; Cannot split
    stderr.write "set with ", paths[0], " .. [", paths.len - 1,
                 "]: too big to sort.  Use a better hash?\n"
    yield paths                                 #Just yield whole set :(

type Digest* = enum size, wy, nim, Sha1 ##Zero,Fast,fast,&slow time hashes
var digSize: array[Digest, int] = [ 0, 8, 8, 20]

template hashAndCpy(hash: untyped) {.dirty.} =
  var h = if b > a: hash(toOpenArray[char](data, a, b - 1)) else: hash("")
  copyMem(addr wkit.dig[8], addr h, digSize[d])

type WorkItem = tuple[sz: int; path, dig: string; m: MFile]
proc digest(wkit: var WorkItem, d: Digest, slice: string) =
  if d != size and (wkit.m := mopen(wkit.path)) == nil:  #maybe open & map file
    perr "digesting ", wkit.path; var zero = 0  #This may run in parallel..so,
    copyMem(addr wkit.dig[0], addr zero, 8)     #use only MT-safe things here.
    return
  let data = cast[ptr UncheckedArray[char]](wkit.m.mem)
  var a, b: int
  parseSlice(slice, wkit.m.len, a, b)           #Apply hash to slice
  copyMem(addr wkit.dig[0], addr wkit.sz, 8)    #Prefix with $sz !=sz => !=dig
  case d                                        #(for putting all in one Table)
  of size: discard
  of wy  : hashAndCpy(hashWY)
  of nim : hashAndCpy(hash)
  of Sha1: hashAndCpy(secureHash)
  if d != size: wkit.m.close()

iterator dupSets*(paths: (iterator(): string), Deref=false, mL=1, slice="",
                  hash=wy, par=false, cmp=false): seq[string] =
  ## Yield paths to sets of duplicate files as seq[string].  See ``proc dups``.
  let sz2paths = getMeta(paths, Deref, mL)
  var m: MFile                                  #Files/size usually < CPU cores
  var wkls: seq[WorkItem]                       #..=>WorkList for files&digests
  for sz, paths in sz2paths:
    if paths.len < 2: continue                  #Unique size=>non-dup; Next!
    if slice.len == 0 and paths.len == 2: #Whole file mode allows doubles optim:
      if fileEq(paths[0], paths[1]):      #..1 cmp ALWAYS less work than 2 hash
        yield paths                       #..MUCH less if files differ early.
      continue                            #Triples inline does not help.
    for p in paths:                       #Build worklist for par mode.
      wkls.add((sz, p, newString(8 + digSize[hash]), m))
  for i in maybePar(par, 0, wkls.len-1):  #hashWY runs@6B/cyc~30GB/s >>IObw =>
    digest(wkls[i], hash, slice)          #..par will help rarely||w/SHA1&!cmp
  let sizeGuess = wkls.len div 2          #pretty good guess if <set.len> =~ 2
  var answer = initTable[string, seq[string]](tables.rightSize(sizeGuess))
  for i in 0 ..< wkls.len:
    answer.mgetOrPut(wkls[i].dig, @[]).add(wkls[i].path)
  for hashSet in answer.values():
    if hashSet.len < 2: continue
    if cmp:
      for subset in carefulSplit(hashSet): yield subset
    else:
      yield hashSet

when isMainModule:                        #Provide a useful CLI wrapper.
  proc dups(file="", delim='\n', Deref=false, minLen=1, slice="", Hash=wy,
            cmp=false, par=false, log={osErr}, brief=false, time="",
            outDlm="\t", endOut="\n", paths: seq[string]): int =
    ## Print sets of paths with duplicate contents. Examined paths are UNION of
    ## `paths` & optional `delim`-delimited input `file` (stdin if "-"|if "" &
    ## stdin not a tty).  Eg., `find -print0|dups -d\\0`.  Exits non-0 if any
    ## dups exist.  Trusting hashes can give false positives, but sorting can
    ## be slow w/many large files of the same size|hash. `slice` can reduce IO,
    ## but can also give false pos. {False negatives not possible. 0 exit =>
    ## surely no dups.}.  Within set sort is by st_blocks if 'summ' is logged,
    ## then by requested file time {'v'time=max(m,c)}, and finally by st_ino.
    dupsLog = log
    let tO = fileTimeParse(time)      #tmUt helper to sort rows by +-[acmv]time
    var tot, nSet, nFile: int         #Track some statistics
    for s in dupSets(both(paths, fileStrings(file, delim)),   #fileStrings,both
                     Deref, minLen, slice, Hash, par, cmp):   #..from osUt
      inc(nSet)
      if brief and summ notin log:
        break                         #Done once we know there is any duplicate
      var ms = s                      #Make mutable copy to hold sorted output
      if time.len > 0 or summ in log: #Re-stat files in s to sort|assess space
        var meta = newSeq[tuple[st: Stat, ix: int]](s.len)
        for i in 0 ..< s.len:         #Stat all again for st_*tim, st_blocks
          meta[i].ix = i
          if stat(s[i], meta[i].st) != 0: perr "stat2 ", s[i]
        if summ in log:               #Total extra space, if requested
          meta = meta.sortedByIt(it.st.st_blocks)  #blocks because sparse files
          for i in 1 ..< s.len: tot += 512 * meta[i].st.st_blocks    #1st=least
          inc(nFile, s.len)
        if time.len > 0:
          meta = meta.sortedByIt(fileTime(it.st, tO.tim, tO.dir))
          meta = meta.sortedByIt(it.st.st_ino)
        for i in 0 ..< s.len:         #Re-populate mutable paths from sorted
          ms[i] = s[meta[i].ix]
      if not brief:                   #Emit report for set
        stdout.write ms.join(outDlm), endOut
    if summ in log:                   #Emit summ report
      stderr.write tot," extra bytes in ",nSet," sets of ",nFile," files\n"
    return if nSet > 0: 1 else: 0     #Exit with appropriate status

  dispatch(dups, help = {
             "file"  : "optional input (\"-\"|!tty=stdin)",
             "delim" : "input file delimiter (\\0->NUL)",
             "Deref" : "dereference symlinks",
             "minLen": "minimum file size to consider",
             "slice" : "file slice (float|%:frac; <0:tailRel)",
             "Hash"  : "hash function [size|wy|nim|SHA1]",
             "cmp"   : "compare; do not trust hash",
             "par"   : "Use parallelism $OMP_NUM_THREADS",
             "log"   : ">stderr{osErr, summ}",
             "brief" : "do NOT print sets of dups",
             "time"  : "sort each set by file time ([+-][amcv].*)",
             "outDlm": "output internal delimiter",
             "endOut": "output record terminator" })
