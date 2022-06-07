import std/[os, posix, strutils, sets, tables, hashes, sha1, algorithm],
  cligen/[procpool,mfile,mslice,fileUt,strUt, osUt,posixUt,sysUt, dents,statx]

type Lg* = enum osErr, summ                     #A tiny logging system
var dupsLog* = { osErr }
proc perr*(x: varargs[string, `$`]) =           #OS Errors like permissions
  if osErr in dupsLog: stderr.write "dups: "; stderr.write x; stderr.write ": ",
                                    osErrorMsg(osLastError()), "\n"

proc getMeta(paths: seq[string]; file: string; delim: char; recurse,minLen: int;
             follow, xdev, Deref: bool): Table[int, seq[string]] =
  var sz2paths = initTable[int, seq[string]](4096)
  let it = both(paths, fileStrings(file, delim))
  for root in it():
    if root.len == 0: continue                  #Skip any improper inputs
    forPath(root, recurse, true, follow, xdev, false, stderr,
            depth, path, nmAt, ino, dt, st, dfd, dst, did):
      if Deref and st.st_mode.S_ISLNK:          #Maybe stat again based on Deref
        # Second stat on symlinks could likely be converted to one upfront stat
        if fstatat(dfd, path.cstring, st, 0) != 0: perr "fstatat ".cstring, path
      if S_ISREG(st.st_mode) and                #Only meaningful to compare reg
         st.st_size >= minLen and               #One easy way to exclude len0.
         not did.containsOrIncl((st.st_dev, st.stx_ino)): #Keep ONLY 1st Path
        sz2paths.mgetOrPut(int(st.st_size), @[]).add(path)
  result = sz2paths

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

iterator dupSets*(sz2paths: Table[int, seq[string]], slice="",
                  hash=wy, jobs=1, cmp=false): seq[string] =
  ## Yield paths to sets of duplicate files as seq[string].  See ``proc dups``.
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
  if jobs == 1:
    for i in 0 ..< wkls.len: digest(wkls[i], hash, slice)
  else: # hashWY runs@6B/cyc~30GB/s >>IObw => par helps rarely | w/SHA1&!cmp
    var pp = initProcPool((proc(r, w: cint) =
                             let i = r.open(fmRead, osUt.IONBF)
                             let o = w.open(fmWrite, osUt.IOFBF)
                             var ix: int
                             while i.uRd ix:
                               digest wkls[ix], hash, slice
                               discard o.uWr ix; o.urite wkls[ix].dig),
                          framesOb, jobs, aux=int.sizeof + 8 + digSize[hash])
    proc copyBack(s: MSlice) =
      let i = int(cast[ptr int](s.mem)[])
      copyMem wkls[i].dig[0].addr, s.mem +! int.sizeof, 8 + digSize[hash]
    pp.evalOb 0 ..< wkls.len, copyBack    #Send indices, assign digests
  let sizeGuess = wkls.len div 2          #pretty good guess if <set.len> =~ 2
  var answer = initTable[string, seq[string]](sizeGuess)
  for i in 0 ..< wkls.len:
    answer.mgetOrPut(wkls[i].dig, @[]).add(wkls[i].path)
  for hashSet in answer.values():
    if hashSet.len < 2: continue
    if cmp:
      for subset in carefulSplit(hashSet): yield subset
    else:
      yield hashSet

when isMainModule:                        #Provide a useful CLI wrapper.
  proc dups(file="", delim='\n', recurse=1, follow=false, xdev=false,
            Deref=false, minLen=1, slice="", Hash=wy, cmp=false, jobs=1,
            log={osErr}, brief=false, time="",outDlm="\t", endOut="\n",
            paths: seq[string]): int =
    ## Print sets of files with duplicate contents. Examined files are UNION of
    ## *paths* & optional *delim*-delimited input *file* ( `stdin` if "-"|if ""&
    ## `stdin` not a tty ).  Eg., ``find -print0|dups -d\\0``.  **Exits non-0**
    ## if a dup exists.  Trusting hashes can give false positives, but sorting
    ## can be slow w/many large files of the same size|hash. *slice* can reduce
    ## IO, but can also give false pos. {False negatives not possible. 0 exit =>
    ## surely no dups.}. Within-set sort is by `st_blocks` if `summ` is logged,
    ## then by requested file time {v=max(m,c)} & finally by ``st_ino``.
    dupsLog = log
    let tO = fileTimeParse(time)      #tmUt helper to sort rows by +-[acmv]time
    var tot, nSet, nFile: int         #Track some statistics
    for s in dupSets(getMeta(paths, file, delim, recurse, minLen, follow, xdev,
                             Deref), slice, Hash, jobs, cmp):
      inc(nSet)
      if brief and summ notin log:
        break                         #Done once we know there is any duplicate
      var ms = s                      #Make mutable copy to hold sorted output
      if time.len > 0 or summ in log: #Re-stat files in s to sort|assess space
        var meta = newSeq[tuple[st: Stat, ix: int]](s.len)
        for i in 0 ..< s.len:         #Stat all again for st_*tim, st_blocks
          meta[i].ix = i
          if stat(s[i].cstring, meta[i].st) != 0: perr "stat2 ", s[i]
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

  import cligen; dispatch dups, short={"follow": 'F'}, help={
             "file"  : "optional input ( `\"-\"` | !tty = ``stdin`` )",
             "delim" : "input file delimiter; `\\\\0` -> NUL",
             "recurse": "recurse n-levels on dirs; `0`: unlimited",
             "follow": "follow symlinks to dirs in recursion",
             "xdev"  : "block cross-device recursion",
             "Deref" : "dereference symlinks",
             "minLen": "minimum file size to consider",
             "slice" : "file slice (float|%:frac; <0:tailRel)",
             "Hash"  : "hash function `[size|wy|nim|SHA1]`",
             "cmp"   : "compare; do not trust hash",
             "jobs"  : "Use this much parallelism",
             "log"   : ">stderr{ `osErr`, `summ` }",
             "brief" : "do NOT print sets of dups",
             "time"  : "sort each set by file time: `{-}[bamcv].\\*`",
             "outDlm": "output internal delimiter",
             "endOut": "output record terminator"}
