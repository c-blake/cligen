import std/[strutils,os,hashes,sets],cligen/[osUt,mslice] #% exec* mdOpen split
from cligen/parseopt3 import optionNormalize

proc toDef(fields, delim, genF: string): string =
  result.add "char const * const rpNmFields = \"" & fields & "\";\n"
  let sep = initSep(delim)
  let row = fields.toMSlice
  var s: seq[MSlice]
  var nms: HashSet[string]
  sep.split(row, s) # No maxSplit - define every field; Could infer it from the
  for j, f in s:    #..highest referenced field with a `where` & `stmts` parse.
    let nm = optionNormalize(genF % [ $f ])   # Prevent duplicate def errors..
    if nm notin nms:                          #..and warn users about collision.
      result.add "int const " & nm & " = " & $j & ";\n"
      nms.incl nm
    else:
      stderr.write "crp: WARNING: ", nm, " collides with earlier field\n"

proc crp(prelude="", begin="", where="1", stmts:seq[string], epilog="",
         fields="", genF="$1", comp="", run=true, args="", outp="/tmp/crpXXX",
         input="/dev/stdin", delim=" \t", uncheck=false, maxSplit=0): int =
  ## Gen+Run *prelude*,*fields*,*begin*,*where*,*stmts*,*epilog* row processor
  ## against *input*.  Defined within *where* & every *stmt* are:
  ##   *s[idx]* & *row* => C strings, *i(idx)* => int64, *f(idx)* => double.
  ##   *nf* & *nr* (*AWK*-ish), *rowLen*=strlen(row);  *idx* is **0-origin**.
  ## A generated program is left at *outp*.c, easily copied for "utilitizing".
  ## If you know *AWK* & C, you can learn *crp* PRONTO.  Examples (need data):
  ##   **seq 0 1000000|crp -w'rowLen<2'**                # Print short rows
  ##   **crp 'printf("%s %s\\n", s[1], s[0]);'**         # Swap field order
  ##   **crp -b'int t=0' t+=nf -e'printf("%d\\n", t)'**  # Prn total field count
  ##   **crp -b'int t=0' -w'i(0)>0' 't+=i(0)' -e'printf("%d\\n", t)'** # Total>0
  ##   **crp 'float x=f(0)' 'printf("%g\\n", (1+x)/x)'** # cache field 0 parse
  ##   **crp -d, -fa,b,c 'printf("%s %g\\n",s[a],f(b)+i(c))'**  # named fields
  ## Add niceties (eg. `#include "mystuff.h"`) to *prelude* in ~/.config/crp.
  let fields = if fields.len == 0: fields else: toDef(fields, delim, genF)
  let check  = if fields.len == 0: "    " elif not uncheck: """
    if (nr == 0) {
      if (strcmp(row, rpNmFields) == 0) {
        nr++; continue; // {fields} {!uncheck}
      } else {
        fprintf(stderr, "row0 \"%s\" != \"%s\"\n", row, rpNmFields); exit(1);
      }
    }
    """ else: "    "
  var program = """#include <stdio.h>
#include <string.h>
#include <stdlib.h>
ssize_t write(int, char const*, size_t);
void _exit(int);
$1 // {prelude}

// Putting below in Ahead-Of-Time optimized .so can be ~2X lower overhead.
char **rpNmSplit(char **toks, size_t *nAlloc,
                 char *str, const char *dlm, long maxSplit, size_t *nSeen) {
  size_t n = 0; /* num used (including NULL term) */
  char  *p;
  if (!toks) {  /* Number of columns should rapidly achieve a steady-state. */
    *nAlloc = 8;
    toks = (char **)malloc(*nAlloc * sizeof *toks);
  }
  if (maxSplit < 0) {
    if ((n=2) > *nAlloc && !(toks=realloc(toks, (*nAlloc=n) * sizeof*toks))) {
      write(2, "out of memory\n", 14);
      _exit(3); /* gen-time maxSplit<0 *could* skip this or rpNmSplit(), but..*/
    }           /*..instead we keep it so user-code referencing s[0] is ok. */
    toks[0] = str; toks[1] = NULL; *nSeen = 1;
    return toks;
  }
  for (toks[n]=strtok_r(str, dlm, &p); toks[n] && (maxSplit==0 || n < maxSplit);
       toks[++n]=strtok_r(0, dlm, &p))
    if (n+2 > *nAlloc && !(toks=realloc(toks, (*nAlloc *= 2) * sizeof*toks))) {
      write(2, "out of memory\n", 14);
      _exit(3);
    }
  *nSeen = n;
  return toks;
}

// {fields}
$2
int main(int ac, char **av) {
  char  **s = NULL, *row = NULL; // CREATE TERSE NOTATION: row/s/i/f/nr/nf
  ssize_t rowLen;
  size_t  rpNmAlloc = 0, nr = 0, nf = 0;
  #define i(j) atoi(s[j])
  #define f(j) atof(s[j])
$4; // {begin}
  FILE *rpNmFile = fopen("$5", "r"); // {input} from stdio
  if (!rpNmFile) {
    fprintf(stderr, "cannot open \"$5\"\n");
    exit(2);
  }
  while ((rowLen = getline(&row, &rpNmAlloc, rpNmFile)) > 0) {
    row[--rowLen] = '\0';       // chop newline
${6}s = rpNmSplit(s, &rpNmAlloc, row, "$3", $7, &nf); // {delim,maxSplit}
    if ($8) { // {where} auto ()s?
""" % [prelude, fields, delim, indent(begin, 2), input, check, $maxSplit, where]
  for i, stmt in stmts:
    program.add "      " & stmt & "; // {stmt" & $i & "}\n"
  if stmts.len == 0:
    program.add "      fwrite(row, rowLen, 1, stdout); fputc('\\n', stdout);\n"
  program.add "    }\n    nr++;\n  }\n"
  program.add indent(epilog, 2)
  program.add "; // {epilogue}\n}\n"
  let mode = if run: "-run" else: ""
  let args = if args.len > 0: args else: "-I$HOME/s -O"
  let digs = count(outp, 'X')
  let hsh  = toHex(program.hash and ((1 shl 16*digs) - 1), digs)
  let outp = if digs > 0: outp[0 ..< ^digs] & hsh else: outp
  let comp = if comp.len > 0: comp else: "tcc $1 $2 -o$3 $4" % [
                                         mode, args, outp, outp & ".c"]
  let f = mkdirOpen(outp & ".c", fmWrite)
  f.write program
  f.close
  execShellCmd(comp & (if run: " < " & input else: ""))

when isMainModule:
  import cligen; include cligen/mergeCfgEnv; dispatch crp, help={
    "stmts"   : "C stmts to run under `where`",
    "prelude" : "C code for prelude/include section",
    "begin"   : "C code for begin/pre-loop section",
    "where"   : "C code for row inclusion",
    "epilog"  : "C code for epilog/end loop section",
    "fields"  : "`delim`-sep field names (match row0)",
    "genF"    : "make field names from this fmt; eg c$1",
    "comp"    : "\"\" => tcc {if run: \"-run\"} {args}",
    "run"     : "Run at once using tcc -run .. < input",
    "args"    : "\"\" => -I$HOME/s -O",
    "outp"    : "output executable; .c NOT REMOVED",
    "input"   : "path to read as input",
    "delim"   : "inp delim chars for strtok",
    "uncheck" : "do not check&skip header row vs fields",
    "maxSplit": "max split; 0 => unbounded"}
