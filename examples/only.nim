import posix, re, strutils, tables, cligen, cligen/[osUt,mslice,magic,procpool]

type Excl = enum compress,tar,soft,apptype,elf,text,cdf,tokens,encoding,ascii
const e2Flag = {  # CSV & json missing; Maybe cligen/magic needs updating?
  apptype : MAGIC_NO_CHECK_APPTYPE , ascii   : MAGIC_NO_CHECK_ASCII   ,
  encoding: MAGIC_NO_CHECK_ENCODING, tokens  : MAGIC_NO_CHECK_TOKENS  ,
  cdf     : MAGIC_NO_CHECK_CDF     , compress: MAGIC_NO_CHECK_COMPRESS,
  elf     : MAGIC_NO_CHECK_ELF     , soft    : MAGIC_NO_CHECK_SOFT    ,
  tar     : MAGIC_NO_CHECK_TAR     , text    : MAGIC_NO_CHECK_TEXT    }.toTable

var gPats: seq[RegEx]
var gAll, gNo: bool
var gFlags = cint(0)

proc any(fileType: string): bool {.inline.} =
  for pat in gPats:
    if fileType.find(pat) != -1: return true

proc all(fileType: string): bool {.inline.} =
  for pat in gPats:
    if fileType.find(pat) == -1: return false
  result = true

proc classifyAndMatch() =
  const TERM = "\0"
  var m = magic_open(gFlags)
  if m == nil or magic_load(m, nil) != 0:
    stderr.write "cannot load magic DB: %s\x0A", m.magic_error, "\n"
    quit(1)
  for path in stdin.getDelim('\0'):
    if path.len == 0:
      quit(0)
    let fileType = $m.magic_file(path)
    if fileType.len == 0:
      stderr.write "UNCLASSIFIABLE: ", path, "\n"
    if gAll:
      if gNo:
        if not all(fileType): stdout.urite path, TERM
      else:
        if all(fileType): stdout.urite path, TERM
    else:
      if gNo:
        if not any(fileType): stdout.urite path, TERM
      else:
        if any(fileType): stdout.urite path, TERM

proc print(s: MSlice, eor: char) {.inline.} = 
  let eos = cast[uint](s.mem) + cast[uint](s.len)
  cast[ptr char](eos)[] = eor
  discard stdout.uriteBuffer(s.mem, s.len + 1)

proc only*(gen="find $1 -print0", dlr1=".", trim="./", eor='\n',
           all=false, no=false, insens=false, excl: set[Excl]={},
           jobs=0, patterns: seq[string]) =
  ## Use ``gen`` and ``dlr1`` to generate paths, maybe skip ``trim`` and then
  ## emit any path (followed by ``eor``) whose `file(1)` type matches any listed
  ## pattern.  ``all`` & ``no`` can combine to mean not all patterns match.
  ##
  ## `file(1)` is very CPU bound & a 4-64x parallel speed-up can help!  The
  ## similar find | xargs -PN file -n -F:XxX: | grep ":XxX: .*$@" | sed -e
  ## 's/:XxX: .*$//' jumbles output { |grep fills up, writers sleep & then awake
  ## in any order }.  Non-portable Linux O_DIRECT flag on pipes might work, but
  ## also needs a manual pipeline build.  This runs in forked kids since
  ## libmagic is NOT MT-SAFE.
  if patterns.len == 0:
    return
  gAll = all; gNo = no                          # Copy to globals
  let trimLen = trim.len
  let flags = {reStudy} + (if insens: {reIgnoreCase} else: {})
  for r in patterns:
    gPats.add re(r, flags)
  for e in excl:
    gFlags = gFlags or cint(e2Flag[e])
  let inp = popen(gen % dlr1, "r")
  var pp = initProcPool(classifyAndMatch, jobs)
  var i = 0
  for path in inp.getDelim('\0'):
    if path.startsWith(trim):                   # Let a full pipe block
      pp.request(i, cstring(path[trimLen..^1]), path.len + 1 - trimLen)
    else:
      pp.request(i, cstring(path), path.len + 1)
    i = (i + 1) mod pp.len
    if i + 1 == pp.len:                         # At the end of each req cycle
      for answer in pp.readyReplies:            #..handle ready replies.
        answer.print eor
  for i in 0 ..< pp.len:                        # Terminate input requests
    pp.request(i, cstring(""), 1)
  for answer in pp.finalReplies:                # Handle final replies
    answer.print eor
  discard inp.pclose

when isMainModule:
  dispatch(only, help={ "gen"   : "generator cmd with dlr1 -> $1",
                        "dlr1"  : "$1 for gen fmt; Eg. *\". -type f\"*",
                        "trim"  : "output pfx to trim (when present)",
                        "eor"   : "end of record delim; Eg.*'\\\\0'*",
                        "all"   : "*all* patterns match (vs. *any*)",
                        "no"    : "*no* patterns match (vs. *any*)",
                        "insens": "regexes are case-insensitive",
                        "excl"  : "tests to exclude like `file(1)`",
                        "jobs"  : "use this many kids (0=auto)" },
           short = {"excl": 'x'})