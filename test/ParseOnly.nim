#Some people want `cligen` for CLI-only modules WITHOUT also retaining good API
#callability.  Personally, I'd discourage this, but there may be good reasons.
#
#In this mode of writing a CLI app with `cligen`, one can handle parse-time
#control flow decisions by passing a `setByParse` to `dispatch(foo)` as shown
#below.  This will cause a `dispatch` to generate a parser-dispatcher which
#returns to the caller on abnormal exit rather than raising an exception.
#If everything goes smoothly the wrapped function is still called, though,
#*unless* `parseOnly=true` is passed.

import cligen

var fooParse: seq[ClParse]

proc foo(alpha: int, beta: int=2, rest: seq[int]) =
  if "alpha" in fooParse:
    echo "user sets of alpha saw these value strings: "
    for s in fooParse:
      if s.paramName == "alpha": echo "  ", s
  if "beta" notin fooParse:
    echo "proc-default value for beta"
  if fooParse.numOfStatus({clBadKey, clBadVal}) > 0:
    echo "There was some kind of parse error."
  echo "full parameter parse:", fooParse
  echo "alpha: ", alpha                     #Main logic
  echo "beta: ", beta

dispatchGen(foo, setByParse=addr fooParse)
dispatchfoo(parseOnly=true)   #cmdLine=os.commandLineParams() by default

echo "fooParse:"
for e in fooParse: echo "  ", e

if fooParse.numOfStatus({clOk, clPositional}) == fooParse.len:
  echo "would have called foo"
else:
  echo "would not have called foo"

if clHelpOnly in fooParse:
  echo "User requested help.  Here you go"
  echo fooParse[fooParse.next({clHelpOnly})].message
  quit(0)

if clVersionOnly in fooParse:
  echo "User requested version only - NO dispatch TO foo WAS DONE"

#While I understand that this mode of usage still leverages the already-known-
#to-any-Nim-programmer declarative syntax for parameters & defaults, note that
#a regular Nim proc does not know how its parameters were set - by default, by
#position, by keyword, or if by keyword, in what order.  Writing this kind of
#definitely-only-a-command user interface can easily block certain functionality
#from being Nim-callable which can be a pain point in the long run.
#
#Also, if you are really deciding much logic based on *specifically how* users
#entered data, you may prefer just using `parseopt3` (or even the Nim stdlib
#`parseopt`).  You can still use `argcvt`, even without the `dispatch` system.
#Compile any `dispatch`-using program with `-d:printDispatch` to see how.
