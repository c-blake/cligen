type Age = distinct int

proc main(age: Age)=
  echo if int(age) == 4: 1 else: 2

import cligen, cligen/argcvt

proc argParse(dst: var Age, dfl: Age, a: var ArgcvtParams): bool =
  var iDst: int
  result = argParse(iDst, int(dfl), a)
  dst = Age(iDst)

proc argHelp(dfl: Age; a: var ArgcvtParams): seq[string] =
  argHelp(int(dfl), a)

dispatch(main)
