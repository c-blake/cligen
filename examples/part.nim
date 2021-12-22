import std/[os, cpuinfo, strformat, strutils, memfiles], cligen/[mslice, osUt]

proc part(n=1, fmt="02d", output="$d$n/$b$e", separator='\n', initial=0,
          print=false, paths: seq[string]): int =
  ## This splits files into parts, like `split -nCHUNKS` but this can replicate
  ## a file header of `initial` lines to each part, print pretend runs, has user
  ## tunable number padding, and output path building.
  let n = if n == 0: countProcessors() else: n
  for path in paths:
    let (dirOnly, base, ext) = path.splitPathName
    var dir = dirOnly
    if dir.len > 0: dir.add DirSep
    var m: MemFile
    try:
      m = memfiles.open(path)
    except OSError as e:
      stderr.write "Cannot mmap \"",path,"\": ",e.msg,"\n"
      continue
    let head = MSlice(mem: m.mem, len: m.size).firstN(initial, term=separator)
    for i, s in nSplit(n, MSlice(mem: m.mem, len: m.size), separator):
      var si: string; si.formatValue i, fmt
      let opath = output % ["d",dir, "b",base, "e",ext, "n",si]
      if print:
        echo s.len, " bytes from ", cast[uint](s.mem) - cast[uint](m.mem),
             " -> ", opath
      else: # Could parallelize this fruitfully depending upon IO dev traits.
        let f = mkdirOpen(opath, fmWrite, bufSize=65536)
        if head.len > 0 and i > 0: f.urite head
        f.urite s
        f.close
    m.close

when isMainModule: import cligen; dispatch part, help={
  "paths"    : "paths to mmap as input",
  "n"        : "number of output parts; 0 => num CPUs",
  "fmt"      : "std fmt specifier for part numbers",
  "output"   : "d/b/e/n=dir/base/ext/n=part number",
  "separator": "delimiter character for rows/records",
  "initial"  : "copy `initial` to start of each output",
  "print"    : "pretend/print work instead of doing it" },
  short={"separator": 't'}
