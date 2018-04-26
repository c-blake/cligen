## This module defines an argParse/argHelp pair for seq[T] where input syntax
## is what I call delimiter-prefixed-separated-value (DPSV) format:
##   <DELIM-CHAR><COMPONENT><DELIM-CHAR><COMPONENT>..
## E.g., for CSV after the first character, one types ",Howdy,Neighbor".
##
## At the cost of one extra character, this lets users choose non-conflicting
## delimiters on a case-by-case basis which means quoting rules are unneeded.
## To activate this syntax, just ``import cligen, argSeqDPSV``.
##
## To allow easy appending to or removing from existing sequence values,
## the characters ``'+'`` and ``'-'`` are not allowed as delimiters.  So,
## e.g., ``-o=,1,2,3 -o=+,4,5, -o=-3`` is equivalent to ``-o=,1,2,4,5``.
## It is not considered an error to try to delete a non-existent value.
##
## Shell glob metacharacters are often inconvenient choices for
## metacharacters, but a few good choices are ',', '@', '%', and ':'.

from argcvt import keys, argRet, argRq

template argParse*(dst: seq[string], key: string, dfl: seq[string],
                   val, help: string) =
  block:
    type argSeqMode = enum Set, Append, Delete
    var mode = Set
    var origin = 0
    if val[0] == '+':
      mode = Append
      origin = 1
    elif val[0] == '-':
      mode = Delete
      origin = 1
    let delim = val[origin]
    if val == nil:
      argRet(1, "Bad value nil for DPSV param \"$1\"\n$2" % [ key, help ])
    var tmp = val[origin + 1..^1].split(delim)
    case mode
    of Set: dst = tmp
    of Append:
      if dst == nil:
        dst = @[ ]
      dst.add(tmp)
    of Delete:
      if dst != nil:
        for i, e in dst:
          if e in tmp:
            dst.del(i)
      else:
        dst = @[ ]

template argHelp*(ht: seq[seq[string]], dfl: seq[string];
                  parNm, sh, parHelp: string, rq: int) =
  block:
    let Dfl = if dfl == nil: @[ "" ] else: dfl
    var delim = "<D>"
    for delimTry in [",", "@", "%", ":", "_", "=", "~", "^" ]:
      if delimTry notin Dfl:
        break
    ht.add(@[ keys(parNm, sh), "DPSV",
              argRq(rq, "\"" & delim & Dfl.join(delim) & "\""), parHelp])
