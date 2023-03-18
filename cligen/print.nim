## Sometimes one does much fast & furious weakly formatted echos and it can be
## tiresome to always put in spaces or formatting.  Languages like Python
## popularized a low ceremony auto-spacing print.  So, here you go.
##
## Note that we *do not* try to mimic the inconvenient Python API.  In my
## experience, traits in the flush/sep family do not vary per-call but rather
## per whole program (or at least per whole `File`, but wrapping that or keeping
## a `Table[File,...]` also seems inconvenient/error prone).  E.g., you may want
## `printsFlush==true` to debug yet in production want buffering for speed.  A
## simple global mode flag is much less work to flip than wrapping/editing all
## call sites -- it could even be a command option!  Contrariwise, when this is
## *not* true, it seems likely you would want to leave it `printsFlush==false`
## and call `flushFile` on your own.  One also rarely changes `printsSep`.  The
## whole point is some simple, default spacing.  If you change that you may as
## well do a `strformat &"thing"`.  Feel free to disgree with me and write your
## own.  If you are porting a bunch of Python code nimpylib may be more useful.
##
## Auto-line ending & target `File` s do vary, though.  For these we just use
## more proc names (there are only 3x2). These lean upon pre-established naming
## conventions like `echo -n` on Unix & fprintf in C for (maybe) easier recall.
when not declared(File): import std/syncio

var printsFlush* = false ## fprint flush behavior
var printsSep* = " "     ## fprint separation string

proc fprintEF*(eol: string, f: File, a: varargs[string, `$`]) =
  ## Like `write` but automatically space-separate parameters.
  for i, x in pairs(a):
    if i != 0: f.write printsSep
    f.write x
  f.write eol
  if printsFlush: flushFile f

proc fprint*(f: File, a: varargs[string, `$`]) = fprintEF "\n", f, a
  ## wrapper around fprintEF to send to `File f`.
proc fprintn*(f: File, a: varargs[string, `$`]) = fprintEF "", f, a
  ## wrapper around fprintEF to send to `File f` with no line ending.

proc print*(a: varargs[string, `$`]) = fprintEF "\n", stdout, a
  ## wrapper around fprintEF to send to stdout.
proc printn*(a: varargs[string, `$`]) = fprintEF "", stdout, a
  ## wrapper around fprintEF to send to stdout with no line ending.

proc eprint*(a: varargs[string, `$`]) = fprintEF "\n", stdout, a
  ## wrapper around fprintEF to send to stderr.
proc eprintn*(a: varargs[string, `$`]) = fprintEF "", stderr, a
  ## wrapper around fprintEF to send to stderr with no line ending.

when isMainModule:
  printn  1, 2
  print   "", 3, 4  # One *could* track state to make "" unneeded, but..
  eprintn 5, 6
  eprint  "", 7, 8  #..this strikes me as unwise/off point of `echo -n`
  printsSep = "\t"
  printn  1, 2; print  "", 3, 4
  eprintn 5, 6; eprint "", 7, 8
# printsFlush = true # eh; must rely upon command caller re-directing, but
                     #..things gone wrong seem unlikely to be from 1-if stmt.
  printsSep = " "
  stdout.fprintn  1, 2
  stdout.fprint  "", 3, 4
