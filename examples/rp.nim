import std/[strutils,os,hashes,sets],cligen/[osUt,mslice] #% exec* mdOpen split
from cligen/parseopt3 import optionNormalize

proc toDef(fields, delim, genF: string): string =
  result.add "const rpNmFieldB {.used.} = \"" & fields & "\"\n"
  result.add "let   rpNmFields {.used.} = rpNmFieldB.toMSlice\n"
  let sep = initSep(delim)
  let row = fields.toMSlice
  var s: seq[MSlice]
  var nms: HashSet[string]
  sep.split(row, s) # No maxSplit - define every field; Could infer it from the
  for j, f in s:    #..highest referenced field with a `test` & `stmts` parse.
    let nm = optionNormalize(genF % [ $f ])   # Prevent duplicate def errors..
    if nm notin nms:                          #..and warn users about collision.
      result.add "const " & nm & " {.used.} = " & $j & "\n" #XXX strop, too?
      nms.incl nm
    else:
      stderr.write "rp: WARNING: ", nm, " collides with earlier field\n"

proc rp(prelude="", begin="", test="true", stmts:seq[string], epilog="",
        fields="",genF="$1",nim="",run=true,args="",verbose=0,outp="/tmp/rpXXX",
        input="/dev/stdin", delim="white", uncheck=false, maxSplit=0): int =
  ## Gen+Run *prelude*,*fields*,*begin*,*test*,*stmts*,*epilog* row processor
  ## against *input*.  Defined within *test* & every *stmt* are:
  ##   *s[fieldIdx]* & *row* give `MSlice` (*$* to get a Nim *string*)
  ##   *i(fieldIdx)* gives a Nim int, *f(fieldIdx)* a Nim float.
  ##   *nf* & *nr* (like *AWK*);  NOTE: *fieldIdx* is **0-origin**.
  ## A generated program is left at *outp*.nim, easily copied for "utilitizing".
  ## If you know *AWK* & Nim, you can learn *rp* PRONTO.  Examples (need data):
  ##   **rp 'echo s[1]," ",s[0]'**                     # Swap field order
  ##   **rp -t'nr mod 100==0' 'echo row'**             # Print each 100th row
  ##   **rp -b'var t=0' t+=nf -e'echo t'**             # Print total field count
  ##   **rp -b'var t=0' -t'i(0)>0' t+=0.i -e'echo t'** # Total >0 field0 ints
  ##   **rp -p'import stats' -b'var r: RunningStat' 'r.push 0.f' -e'echo r'**
  ##   **rp 'let x=f(0)' 'echo (1+x)/x'**              # cache field 0 parse
  ##   **rp -d, -fa,b,c 'echo s[a],f(b)+i(c).float'**  # named fields (CSV)
  ## Add niceties (eg. `import lenientops`) to *prelude* in ~/.config/rp.
  if stmts.len == 0: stderr.write "rp -h for help\n"; return 1
  let fields = if fields.len == 0: fields else: toDef(fields, delim, genF)
  let check  = if fields.len == 0: "    " elif not uncheck: """
    if nr == 0:
      if row == rpNmFields: inc nr; continue # {fields} {!uncheck}
      else: stderr.write "row0 \"",row,"\" != \"",rpNmFields,"\"\n"; quit 1
    """ else: "    "
  var program = """import cligen/[mfile, mslice]
$1 # {prelude}
# {fields}
$2 
proc main() =
  var s: seq[MSlice] # CREATE TERSE NOTATION: row/s/i/f/nr/nf
  func i(j: int): int   {.used.} = parseInt(s[j])
  func f(j: int): float {.used.} = parseFloat(s[j])
  var nr = 0
  let rpNmSepOb = initSep("$3") # {delim}
$4 # {begin}
  for row in mSlices("$5", eat='\0'): # {input} mmap|slices from stdio
${6}rpNmSepOb.split(row, s, $7) # {maxSplit}
    let nf {.used.} = s.len
    if $8: # {test} auto ()s?
""" % [prelude, fields, delim, indent(begin, 2), input, check, $maxSplit, test]
  for i, stmt in stmts:
    program.add "      " & stmt & " # {stmt" & $i & "}\n"
  if stmts.len == 0:
    program.add "      discard\n"
  program.add "    inc nr\n"
  program.add indent(epilog, 2)
  program.add " # {epilogue}\n\nmain()\n"
  let bke  = if run: "r" else: "c"
  let args = if args.len > 0: args else: "-d:danger --gc:arc"
  let verb = "--verbosity:" & $verbose
  let digs = count(outp, 'X')
  let hsh  = toHex(program.hash and ((1 shl 16*digs) - 1), digs)
  let outp = if digs > 0: outp[0 ..< ^digs] & hsh else: outp
  let nim  = if nim.len > 0: nim else: "nim $1 $2 $3 -o:$4 $5" % [
                                       bke, args, verb, outp, outp]
  let f = mkdirOpen(outp & ".nim", fmWrite)
  f.write program
  f.close
  execShellCmd(nim & (if run: " < " & input else: ""))

when isMainModule:
  import cligen; include cligen/mergeCfgEnv
  dispatch rp, help={"prelude" : "Nim code for prelude/imports section",
                     "begin"   : "Nim code for begin/pre-loop section",
                     "test"    : "Nim code for row inclusion",
                     "stmts"   : "Nim stmts to run under test",
                     "epilog"  : "Nim code for epilog/end loop section",
                     "fields"  : "`delim`-sep field names (match row0)",
                     "genF"    : "make field names from this fmt; eg c$1",
                     "nim"     : "\"\" => nim {if run: r else: c} {args}",
                     "run"     : "Run at once using nim r .. < input",
                     "args"    : "\"\" => -d:danger --gc:arc",
                     "verbose" : "Nim compile verbosity level",
                     "outp"    : "output executable; .nim NOT REMOVED",
                     "input"   : "path to mmap|read as input",
                     "delim"   : "inp delim chars; Any repeats => fold",
                     "uncheck" : "do not check&skip header row vs fields",
                     "maxSplit": "max split; 0 => unbounded"}
