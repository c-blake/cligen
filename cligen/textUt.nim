from strutils import split, wordWrap, repeat
from terminal import terminalWidth

proc addPrefix*(prefix: string, multiline=""): string =
  result = ""
  var lines = multiline.split("\n")
  if len(lines) > 1:
    for line in lines[0 .. ^2]:
      result &= prefix & line & "\n"
  if len(lines) > 0:
    if len(lines[^1]) > 0:
      result &= prefix & lines[^1] & "\n"

type TextTab* = seq[seq[string]]

proc alignTable*(tab: TextTab, prefixLen=0, colGap=2, minLast=16, rowSep="",
                 cols = @[0,1]): string =
  result = ""
  proc nCols(): int =
    result = 0
    for row in tab: result = max(result, row.len)
  var wCol = newSeq[int](nCols())
  let last = cols[^1]
  for row in tab:
    for c in cols[0 .. ^2]: wCol[c] = max(wCol[c], row[c].len)
  var wTerm = terminalWidth() - prefixLen
  var leader = (cols.len - 1) * colGap
  for c in cols[0 .. ^2]: leader += wCol[c]
  wCol[last] = max(minLast, wTerm - leader)
  for row in tab:
    for c in cols[0 .. ^2]:
      result &= row[c] & repeat(" ", wCol[c] - row[c].len + colGap)
    var wrapped = wordWrap(row[last], maxLineWidth = wCol[last]).split("\n")
    result &= (if wrapped.len > 0: wrapped[0] else: "") & "\n"
    for j in 1 ..< len(wrapped):
      result &= repeat(" ", leader) & wrapped[j] & "\n"
    result &= rowSep
