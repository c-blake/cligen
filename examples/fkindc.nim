import std/[posix, strutils, tables], cligen/[osUt, mslice, magic, procpool]

type Excl = enum compress,tar,soft,apptype,elf,text,cdf,tokens,encoding,ascii
const e2Flag = {  # CSV & json missing; Maybe cligen/magic needs updating?
  apptype : MAGIC_NO_CHECK_APPTYPE , ascii   : MAGIC_NO_CHECK_ASCII   ,
  encoding: MAGIC_NO_CHECK_ENCODING, tokens  : MAGIC_NO_CHECK_TOKENS  ,
  cdf     : MAGIC_NO_CHECK_CDF     , compress: MAGIC_NO_CHECK_COMPRESS,
  elf     : MAGIC_NO_CHECK_ELF     , soft    : MAGIC_NO_CHECK_SOFT    ,
  tar     : MAGIC_NO_CHECK_TAR     , text    : MAGIC_NO_CHECK_TEXT    }.toTable

var gFlags = 0.cint
proc count(histo: var CountTable[string], s: MSlice) = histo.inc $s

proc classify(r, w: cint) = # Reply with same path as input if it passes filter.
  var m = magic_open(gFlags)
  if m == nil or magic_load(m, nil) != 0:
    stderr.write "cannot load magic DB: %s\n\t", m.magic_error, "\n"
    quit 1
  for path in r.open.getDelim('\0'):
    let fileType = $m.magic_file(path.cstring)
    discard wrLenBuf(w, fileType)

proc fkindc*(gen="find $1 -print0", dlr1=".", excl: set[Excl]={}, jobs=0) =
  ## Use ``gen`` and ``dlr1`` to generate paths and histogram by `file(1)` type.
  var histo: CountTable[string]
  for e in excl: gFlags = gFlags or cint(e2Flag[e]) # Set up gFlags for libmagic
  let inp = popen(cstring(gen % dlr1), "r".cstring) # Fire input path generator
  var pp = initProcPool(classify, framesLenPfx, jobs) # Start & drive kids
  pp.eval0term(inp.getDelim('\0'), histo.count)     # Replies=0-term file types
  discard inp.pclose
  histo.sort
  for k, ct in histo: echo ct, '\t', k

when isMainModule:
  import cligen; dispatch fkindc, short={"excl": 'x'}, help={
    "gen" : "generator cmd with dlr1 -> $1",
    "dlr1": "$1 for gen fmt; Eg. *\". -type f\"*",
    "excl": "tests to exclude like `file(1)`",
    "jobs": "use this many kids (0=auto)" }
