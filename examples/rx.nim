import std/[strutils, os, hashes], cligen/osUt # `%`, execShellCmd, hash(string)

# Order of params is: generation, compilation, running.
proc rx(prelude="", begin="", test="true", stmts: seq[string], epilog="",
        nim="", run=true, args="", verbose=0, outp="/tmp/rxXXX",
        input="/dev/stdin", delim="white", maxSplit=0): int =
  ## Merge *prelude*, *begin*, *test*, *stmts*, *epilog* sections into a Nim row
  ## processer.  Compile & if *run* also run against *input*.  Defined within
  ## *test* & every *stmt* are:
  ##   *s[fieldIdx]* giving an MSlice (*$* that to get a Nim *string*)
  ##   *i(fieldIdx)* to get a Nim int, *f(fieldIdx)* for a Nim float.
  ##   *o* for `stdout`; *e* for `stderr`.
  ##   *nf* & *nr* (like awk, but **0-origin** & lowercase).
  ## A generated program is left at *outp*.nim, easily copied for "utilitizing".
  ## If you know awk & Nim, you can learn this in ~2 minutes; Our data loop
  ## language is just typed Nim.  Examples:
  ##   **rx 'echo s[1]'**                              # Print 2nd field
  ##   **rx -t'nr mod 100==0' 'echo row'**             # Print each 100th row
  ##   **rx -b'var t=0' t+=nf -e'echo t'**             # Print total fields
  ##   **rx -b'var t=0' -t'i(0)>0' t+=0.i -e'echo t'** # Total >0 field0 ints
  ##   **rx -p'import stats' -b'var r: RunningStat' 'r.push 0.f' -e'echo r'**
  ##   **rx 'let x=f(0)' 'echo (1+x)/x'**              # cache field 0 parse
  var program = """import cligen/[mfile, mslice]
$1 # {prelude}

proc main() =
  var  s: seq[MSlice] # CREATE TERSE NOTATION: s/i/f/o/e/nr
  proc i(j: int): int   {.used.} = parseInt(s[j])
  proc f(j: int): float {.used.} = parseFloat(s[j])
  let  o {.used.} = stdout
  let  e {.used.} = stderr
  var  nr = 0

  let sep = initSep("$2") # {delim}
$3 # {begin}
  for row in mSlices("$4", eat='\0'): # {input} mmap|slices from stdio
    sep.split(row, s, $5) # {maxSplit}
    let nf {.used.} = s.len
    if $6: # {test} auto ()s?
""" % [prelude, delim, indent(begin, 2), input, $maxSplit, test]
  for i, stmt in stmts:
    program.add "      " & stmt & " # {stmt" & $i & "}\n"
  program.add "    inc nr\n"
  program.add indent(epilog, 2)
  program.add " # {epilogue}\nmain()"
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
  dispatch rx, help={"prelude" : "Nim code for prelude/imports section",
                     "begin"   : "Nim code for begin/pre-loop section",
                     "test"    : "Nim code for row inclusion",
                     "stmts"   : "Nim stmts to run under test",
                     "epilog"  : "Nim code for epilog/end loop section",
                     "nim"     : "\"\" => nim {if run: r else: c} {args}",
                     "run"     : "Run at once using nim r .. < input",
                     "args"    : "\"\" => -d:danger --gc:arc",
                     "verbose" : "Nim compile verbosity level",
                     "outp"    : "output executable; .nim NOT REMOVED",
                     "input"   : "path to mmap|read as input",
                     "delim"   : "inp delim chars; Any repeats => fold",
                     "maxSplit": "max split to; 0 => unbounded"}
# TODO: One can make this nicer by optionally parsing optional header row (as
# from DSV) & rewriting user references to such headers into field indices.
# The only gotcha is maybe name collisions between headers & our auto-idents
# {[sifoe], row, nr, nf, & sep }; Can just error out on such rare cases.
# Another nice(-ish) feature of awk is autoOpen via its "print foo > path".
# Could add that via `path.F.fprint` where F wraps `Table[string, File]`.
