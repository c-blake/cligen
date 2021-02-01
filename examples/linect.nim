import math, mfile, mslice, osproc, threadpool, cligen

proc doLines(sub: ptr int, c: int, part: MSlice) =
  for s in part.mSlices('\n'): sub[].inc

proc lc(path: string, n: int, untermOk=true, pparts=false): int =
  var (mf, parts) = n.nSplit(path)      # file & sections
  var sub = newSeq[int](parts.len)      # subtotals
  for c, part in parts:
    spawn doLines(sub[c].addr, c, part)
  sync()                                # all finished
  if pparts:
    stdout.write sub.len
    for i in sub: stdout.write " ", i
    stdout.write '\n'
  result = sub.sum
  if (not untermOk) and mf.len > 0 and  # unterm debatable
     cast[ptr char](mf.mem +! (mf.len - 1))[] != '\n':
    result.dec
  mf.close

proc linect(paths: seq[string], nThread=0, untermOk=false, parts=false) =
  ## Like `wc -l` using `nThreads` to (maybe) hasten big files to inspect
  ## workload distribution when `parts` is true.  For example:
  ##   `for n in {1..16}; do printf "$n "; linect -pn$n cligen.nim; done`
  let n = if nThread == 0: countProcessors() else: nThread
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
