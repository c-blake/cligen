proc repro(secondsSpread = 300, `0` = false, b = false) =
  echo "0 is: ", $`0`

import cligen

dispatch(repro, help = {
         "secondsSpread": "length of time window covered by one file",
         "0": "NUL-delimit the file in --outputFile instead of newline-delimiting",
         "b": "single letter parameters don't suffer" })
