import cligen/[procpool, mslice, osUt], cligen

proc term(k: int): float = (0.5 - float(k mod 2))*8'f/float(2*k + 1)

iterator batches(n, batch: int): Slice[int] =
  for start in countup(0, n - 1, batch):
    yield start ..< start+batch

proc piPar(n=30, batch=17, jobs=0): float =
  ## Use en.wikipedia.org/wiki/Leibniz_formula_for_%CF%80 to estimate π like
  ## github.com/status-im/nim-taskpools/blob/stable/examples/e02_parallel_pi.nim
  ## or github.com/nim-lang/Nim/blob/v1.6.2/tests/parallel/tpi.nim do.
  if n > 40: raise newException(HelpError, "n is *log2* terms; Full ${HELP}")
  if batch > n - 3: raise newException(HelpError, "batch too big; Full ${HELP}")
  let n     = 1 shl n
  let batch = 1 shl batch
  if jobs == 1:
    for k in 0 ..< n: result += term(k)
  else:
    var pp = initProcPool( (proc(r, w: cint) =
      let i = open(r)
      let o = open(w, fmWrite)
      var s: Slice[int]
      while i.uRd(s):
        var sub = 0.0
        for k in s: sub += term(k)
        discard o.uWr(sub) ),
      framesOb, jobs, aux=float.sizeof)
    template add(s: MSlice) =
      result += cast[ptr float](s.mem)[]
    pp.evalOb batches(n, batch), add

dispatch piPar, help={"n"    : "lg(number of terms)",
                      "batch": "lg(batch size) (<n-2)",
                      "jobs" : "parallelism"}, echoResult=true
#[ Compiled with `nim r -d:danger`, this should run in ~1..2 sec with -j1 for
   the default 1 GiTerm series in 128 KiTerm batches.  If I run this script:
      #!/bin/bash
      ( for j in `eval echo {1..$(nproc)}`; do
          /usr/bin/time -f%E ./piPar -j$j
        done ) |& grep -v 3.14 | sed 's/0:0//' > /tmp/o.$$
      t1=$(head -n1 < /tmp/o.$$)      # time for -j1
      awk '{print '${t1}'/NR/$1}' < /tmp/o.$$
      rm /tmp/o.$$  # Can drop this, take min of N runs, etc.
on i7-6700K (4-core Intel w/HT off), I get: 1 0.943396 0.833333 0.833333 while
on an AMD 2950X 16/32 w/HT, I get: 1 0.914286 0.901408 0.888889 0.853333 0.8
0.783673 0.727273 0.735632 0.685714 0.646465 0.695652 0.590769 0.653061 0.609524
0.571429 0.537815 0.533333 0.531856 0.505263 0.537815 0.484848 0.491049 0.5 0.48
0.461538 0.474074 0.457143 0.472906 0.426667 0.476427 0.40. ]#
