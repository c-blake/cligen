#Some people want `cligen` for CLI-only modules WITHOUT also retaining good API
#callability.  Personally, I'd discourage this, but there may be good reasons.
#
#In this mode of writing a CLI app with `cligen`, one can handle parse-time
#control flow decisions by passing a `setByParse` to `dispatch(foo)` as shown
#below.

import tables, cligen, cligen/parseopt3, cligen/argcvt, strutils, parseutils

var setByFooParse = initTable[string, seq[string]]()

proc foo(alpha: int=1, beta: int=2) =
  if "alpha" in setByFooParse:
    echo "user sets of alpha saw these value strings: "
    for s in setByFooParse["alpha"]:
      echo "  ", s
  echo alpha, " ", beta

dispatch(foo, setByParse=addr setByFooParse)

#If you are really deciding much logic based on specific entry by users, you
#may prefer using `parseopt3` (or even the Nim stdlib `parseopt`) and `argcvt`
#directly rather than the `dispatch`/`dispatchGen` system.  Compile any
#`dispatch`-using program with `-d:printDispatch` to see what to do.
