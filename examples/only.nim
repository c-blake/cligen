import std/[posix,re,strutils,tables], cligen,cligen/[osUt,mslice,magic,procpool]

type Excl = enum compress,tar,soft,apptype,elf,text,cdf,tokens,encoding,ascii
const e2Flag = {  # CSV & json missing; Maybe cligen/magic needs updating?
  apptype : MAGIC_NO_CHECK_APPTYPE , ascii   : MAGIC_NO_CHECK_ASCII   ,
  encoding: MAGIC_NO_CHECK_ENCODING, tokens  : MAGIC_NO_CHECK_TOKENS  ,
  cdf     : MAGIC_NO_CHECK_CDF     , compress: MAGIC_NO_CHECK_COMPRESS,
  elf     : MAGIC_NO_CHECK_ELF     , soft    : MAGIC_NO_CHECK_SOFT    ,
  tar     : MAGIC_NO_CHECK_TAR     , text    : MAGIC_NO_CHECK_TEXT    }.toTable

var gPats: seq[RegEx]
var gFlags = cint(0)
var gAll, gNo: bool                           # Support Boolean AND/OR/NOT

proc any(fileType: string): bool {.inline.} = # Support Boolean OR
  for pat in gPats:
    if fileType.find(pat) != -1: return true

proc all(fileType: string): bool {.inline.} = # Support Boolean AND
  for pat in gPats:
    if fileType.find(pat) == -1: return false
  result = true

proc classifyAndMatch() = # Reply with same path as input if it passes filter.
  const TERM = "\0"
  var m = magic_open(gFlags)
  if m == nil or magic_load(m, nil) != 0:
    stderr.write "cannot load magic DB: %s\x0A", m.magic_error, "\n"
    quit(1)
  for path in stdin.getDelim('\0'):
    let fileType = $m.magic_file(path)
    if fileType.len == 0:
      stderr.write "UNCLASSIFIABLE: ", path, "\n"
    if gAll:                                    # Handle all 4 Boolean cases
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
  let eos = cast[uint](s.mem) + cast[uint](s.len)   # Hijack end of string here.
  cast[ptr char](eos)[] = eor                       # It won't be used again.
  discard stdout.uriteBuffer(s.mem, s.len + 1)

iterator getNoPfx(stream: File, dlm: char='\n', pfx="./"): string =
  # `find x y -print0` prefixes results with "[xy]/" which can annoy if x=".".
  for path in stream.getDelim(dlm):
    yield (if path.startsWith(pfx): path[pfx.len..^1] else: path)

proc only*(gen="find $1 -print0", dlr1=".", trim="./", eor='\n',
           all=false, no=false, insens=false, excl: set[Excl]={},
           jobs=0, patterns: seq[string]) =
  ## Use ``gen`` and ``dlr1`` to generate paths, maybe skip ``trim`` and then
  ## emit any path (followed by ``eor``) whose `file(1)` type matches any listed
  ## pattern.  ``all`` & ``no`` can combine to mean not all patterns match.
  ##
  ## `file(1)` is *very* CPU bound. Parallel speed-up can help a lot. A
  ## ``find|xargs -PN stdout -oL file -F:Xx:|grep ":Xx: .*$@"|sed -e 's/:Xx:
  ## .*$//'`` is slower & needs :Xx: delimiter; MT-UNSAFE libmagic=>forked kids.
  if patterns.len == 0:
    return
  gAll = all; gNo = no                          # Copy to globals
  let flags = {reStudy} + (if insens: {reIgnoreCase} else: {})
  for r in patterns:                            # Compile pattern recognizers
    gPats.add re(r, flags)
  for e in excl:                                # Set up gFlags for libmagic
    gFlags = gFlags or cint(e2Flag[e])
  let inp = popen(gen % dlr1, "r")              # Fire input path generator
  # Any reply is an `okPath`; `pp.unord` doesn't need a request to have a reply.
  var pp = initProcPool(classifyAndMatch, jobs) # Start & drive process pool
  pp.eval(path, okPath, inp.getNoPfx('\0', trim), okPath.print(eor))
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