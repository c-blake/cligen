import cligen/strUt     # Example/test text template/macro expand/interpolation.

proc render(fmt: openArray[char]): string =
  for (id, arg, call) in tmplParse(fmt):
    if id == 0..0: result.add fmt[arg]
    else:
      case fmt[id].toString
      of "a": result.add "hmm"
      of "bc": result.add "hoo"
      else: result.add fmt[call]

for (n, fmt, expect) in [ # This tests a bunch of cases.  Maybe I missed some?
  ( 0, "hi ${x} ho$y"  ,"hi ${x} ho$y"  ),( 1, "hi $x ho${y}" ,"hi $x ho${y}"),
  ( 2, "$a $bc"        ,"hmm hoo"       ),( 3, "${a} ${bc}"   ,"hmm hoo"),
  ( 4, "hi ${(bc)::}ie","hi hooie"      ),( 5, "hi $bc:ther"  ,"hi hoo:ther"),
  ( 6, "hi ${bc:ther"  ,"hi ${bc:ther"  ),( 7, "hi ${(bc:ther","hi ${(bc:ther"),
  ( 8, "hi ${(bc):ther","hi ${(bc):ther"),( 9, "hi $bc:ther$" ,"hi hoo:ther$"),
  (10, "hi $bc:ther${" ,"hi hoo:ther${" ),(11, "hi ${} ho"    ,"hi ${} ho"),
  (12, "hi $bc:ther${}","hi hoo:ther${}"),(13, "hi $bc:ther$$","hi hoo:ther$"),
  (14, "hi $$ ho"      ,"hi $ ho"       ),(15, "hi ${()}"     ,"hi ${()}")]:
  if (let s = render(fmt); s != expect):
    echo n, " rendered: \"", s, "\" != expected: \"", expect, "\""

## A fancier application is for a macro impl can use its ARG as a nested tmpl
## with another renderer to do: `${(SELECT)x,y FROM Points *** <tr> <td>$1</td>
## <td>$2</td> </tr>}` [ the idea being SELECT splits on "***" then loops over
## query output rendering a post-*** tmpl to fill an HTML table].  That this can
## work is no accident. Call syntax was designed to minimize lexical commitments
## to mingle well with surrounding syntax & to let macros define any sub-syntax
## in ARG.  Semantics/interpretation/render was also intentionally deferred.
