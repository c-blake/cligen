import std/[math, osproc], cligen/[mfile, mslice], cligen

type ThrDat = tuple[part: ptr MSlice, subp: ptr int]
var thrs: seq[Thread[ThrDat]]

proc work(td: ThrDat) {.thread.} =
  var tot = td.subp[]                   # subp[] is part of a dense array
  for s in td.part[].mSlices('\n'):     #..ENSURING cache thrashing.  So,
    tot.inc                             #..shadow w/local updated only once.
  td.subp[] = tot                 

proc lc(path: string, n: int, untermOk=true, pparts=false): int =
  if (var (mf, parts) = n.nSplit(path); mf) != nil:     # file & sections
    var sub = newSeq[int](parts.len)                    # subtotals
    if n > 1:                           # add mf.len > 65536|something?
      for i, part in parts:
        createThread thrs[i], work, (parts[i].addr, sub[i].addr)
      joinThreads thrs                  # all finished
    else:
        work (parts[0].addr, sub[0].addr)
    if pparts:
      stdout.write sub.len
      for i in sub: stdout.write " ", i
      stdout.write '\n'
    result = sub.sum
    if (not untermOk) and mf.len > 0 and  # unterm debatable
       cast[ptr char](mf.mem +! (mf.len - 1))[] != '\n':
      result.dec
    mf.close
  else: stderr.write "linect: \"",path,"\" missing/irregular\n"

proc linect(paths: seq[string], nThread=0, untermOk=false, parts=false) =
  ## Like `wc -l` using `nThreads` to (maybe) hasten big files to inspect
  ## workload distribution when `parts` is true.  For example:
  ##   `for n in {1..16}; do printf "$n "; linect -pn$n cligen.nim; done`
  let n = if nThread == 0: countProcessors() else: nThread
  thrs.setLen n                         # allocate `thrs` & `cnts`
  var total = 0
  for path in paths:
    let m = lc(path, n, untermOk, parts)
    if not parts:
      echo m, " ", path
      total += m
  if not parts and paths.len > 1: echo total, " total"

dispatch(linect, help={"nThread" : "threads to use; 0 = auto",
                       "untermOk": "final unterminated 'line' counts",
                       "parts"   : "print part sizes, not counts"})
