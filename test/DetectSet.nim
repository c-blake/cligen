#Some people want `cligen` for CLI-only modules WITHOUT also retaining good API
#callability.  Personally, I'd discourage this, but there may be good reasons.
#
#In this mode of writing a CLI app with `cligen`, one can handle parse-time
#control flow decisions by re-defining `argParse` between `import cligen/argcvt`
#and `dispatch(foo)`.

import cligen, cligen/parseopt3, cligen/argcvt, strutils, parseutils

var alphaSet = false

proc argParse(dst: var int, dfl: int, a: var ArgcvtParams): bool =
  if a.key == "a" or optionNormalize(a.key) == "alpha":
    alphaSet = true
  let stripped = strip(a.val)
  if len(stripped) == 0 or parseInt(stripped, dst) != len(stripped):
    a.msg = "Bad value: \"$1\" for option \"$2\"; expecting $3\n$4" %
            [ a.val, a.key, "int", a.help ]
    return false
  return true

proc foo(alpha: int=1, beta: int=2) =
  when declared(alphaSet):
    if alphaSet:
      echo "alpha set changed by user."
  echo alpha, " ", beta

dispatch(foo)

#This works in a pinch, but obviously doesn't scale well to all types/option
#keys.  If you are really deciding logic based on specific entry by users in
#many places, though, you would also probably prefer using `parseopt3` (or
#even the Nim stdlib `parseopt`) and `argcvt` directly rather than the
#`dispatch`/`dispatchGen` system.  Compile any `dispatch`-using program with
#`-d:printDispatch` to see what to do.
