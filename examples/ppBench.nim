import std/posix, cligen/[procpool, osUt, posixUt], cligen

var ibuf, obuf: string

proc doIt(r, w: cint) =
  var buf: string
  buf.setLen ibuf.len + 1
  let i = r.open(fmRead)
  let o = w.open(fmWrite)
  while i.ureadBuffer(buf[0].addr, ibuf.len) == ibuf.len:
    discard o.uriteBuffer(obuf[0].addr, obuf.len)

proc ppBench(input=1, output=1, n=500000, jobs=1, rTOms=0, wTOms=0): int =
  ## Measure procpool overhead vs input-output sizes & jobs as specified.
  let rT = Timeval(tv_usec: 1000 * rTOms.clong) # set select timeouts
  let wT = Timeval(tv_usec: 1000 * wTOms.clong)
  for i in 1..max(1, input ): ibuf.add ($i)[^1] # populate dummy buffers with..
  for i in 1..max(1, output): obuf.add ($i)[^1] #..last digits of numbers
  obuf.add '\0'
  iterator genWork: string = (for i in 1..n: yield ibuf)
  let t0 = getTmNs()                            # Time starting kids and..
  var pp = initProcPool(doIt, frames0term, jobs, toR=rT, toW=wT)
  pp.eval0term(genWork(), noop)                 #..then generate & run work.
  echo "amortized dispatch overhead/job (ns): ", int(dtNs(t0).float / n.float)

dispatch ppBench, help={
  "input" : "bytes to input to pipes", "output": "bytes to output to pipes",
  "n"     : "number of jobs to time" , "jobs"  : "this many parallel kids" ,
  "rTOms" : "read select timeout(ms)", "wTOms" : "write select timeout(ms)"}
