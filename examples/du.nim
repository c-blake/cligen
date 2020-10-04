import std/[sets, parseutils, posix, re],
       cligen, cligen/[dents, statx, osUt, posixUt, humanUt]

proc parseSize(size: string): int64 =
  var sz: int
  let used = parseInt(size, sz)
  result = int64(sz)
  if used < size.len:
    case size[used]
    of 'k': result = result shl 10
    of 'm': result = result shl 20
    of 'g': result = result shl 30
    of 't': result = result shl 40
    of 'p': result = result shl 50
    of 'K': result = result * 1_000'i64
    of 'M': result = result * 1_000_000'i64
    of 'G': result = result * 1_000_000_000'i64
    of 'T': result = result * 1_000_000_000_000'i64
    of 'P': result = result * 1_000_000_000_000_000'i64
    else: discard             # Treat bogus suffix like '[bB]'

proc getScale(bytes, kilo, mega, giga, tera, peta, si, humanReadable: bool,
              blockSize: string): uint64 =
  if blockSize.len > 0: return uint64(blockSize.parseSize)
  if humanReadable: return 0
  if bytes: return 1            # Check for conflicting unit scale settings?
  if kilo and si: return 1000'u64
  if mega and si: return 1_000_000'u64
  if mega: return 1'u64 shl 20
  if giga and si: return 1_000_000_000'u64
  if giga: return 1'u64 shl 30
  if tera and si: return 1_000_000_000_000'u64
  if tera: return 1'u64 shl 40
  if peta and si: return 1_000_000_000_000_000'u64
  if peta: return 1'u64 shl 40
  return 1'u64 shl 10

proc emit(inodes, si: bool; tot, scale, scaleA: uint64;
          root, outEnd: string) {.inline.} =
  if inodes: stdout.write tot, "\t", root, outEnd
  elif scale != 0: stdout.write (tot + scaleA) div scale, "\t", root, outEnd
  else: stdout.write humanReadable4(uint(tot), not si), "\t", root, outEnd

proc getExcls(exclude: seq[string], exclFrom: string, delim: char): seq[Regex] =
  for e in exclude:
    result.add e.re
  if exclFrom.len > 0:
    for e in open(exclFrom, fmRead).readAll.split(delim):
      result.add e.re

proc excluded(path: string, excls: seq[Regex]): bool =
  for ex in excls:
    if path.match(ex):
      return true

proc du*(file="",delim='\n',oneFileSystem=false,chase=false, dereference=false,
         apparentSize=false, inodes=false, countLinks=false, excludeFrom="",
         exclude: seq[string] = @[], bytes=false, kilo=false, mega=false,
         giga=false, tera=false, peta=false, blockSize="", summarize=false,
         si=false, humanReadable=false, total=false, outEnd="\n", quiet=false,
         roots: seq[string]): int =
  ## Mostly compatible replacement for GNU ``du`` using my 1.4-2x faster file
  ## tree walk that totals ``st_blocks\*512`` with more/better short options.
  ## Notable differences: drops weakly motivated options {*time*, *[aDHt]*,
  ## *max-depth*, *separate-dirs*}; *outEnd* replaces *null|-0*; patterns are
  ## all PCRE not shell and need ".\*"; *bytes* does not imply *apparent-size*
  ## and *dereference* does not imply *chase*.
  let roots    = if roots.len > 0: roots else: @[ "." ]
  let err      = if quiet: nil else: stderr
  var nErr     = 0
  var grandTot = 0'u64
  let scale    = getScale(bytes, kilo, mega, giga, tera, peta, si,
                          humanReadable, blockSize)
  let scaleA   = scale div 2                    # round to nearest unit
  let excls    = getExcls(exclude, excludeFrom, delim)
  var saw      = initHashSet[tuple[dev: Dev, ino: uint64]]()
  let it       = both(roots, fileStrings(file, delim))
  for root in it():
    if root.len == 0: continue                  # skip any improper inputs
    var tot = 0'u64
    forPath(root, 0, true, chase, oneFileSystem, false, err,
            depth, path, nmAt, ino, dt, lst, dfd, dst, did):
      if not path.excluded(excls):
        if dereference and dt == DT_LNK:
          if fstatat(dfd, path[nmAt..^1].cstring, lst, 0.cint) != 0:
            nErr += 1   # Best effort only; Just use old `lst` if fstatat fails
        if countLinks or not saw.containsOrIncl((lst.st_dev, lst.stx_ino)):
          tot += (if inodes: 1'u64 elif apparentSize: lst.stx_size else:
                  lst.stx_blocks * 512)
    do:
      let sub = tot - (if inodes: 1'u64 elif apparentSize: lst.stx_size else:
                       lst.stx_blocks * 512)
    do:
      if not summarize:
        emit(inodes, si, tot - sub, scale, scaleA, path, outEnd)
    do: recFailDefault("du", path)
    if summarize:
      emit(inodes, si, tot, scale, scaleA, root, outEnd)
    if total:
      grandTot += tot
  if total:
    emit(inodes, si, grandTot, scale, scaleA, "total", outEnd)
  return min(nErr, 255)

when isMainModule:
  dispatch(du,
           short={"oneFileSystem":'x', "dereference":'L', "countLinks":'l',
                  "excludeFrom":'X', "blockSize":'B', "help":'?', "total":'c'},
           help = {
             "file"           : "optional input (\"-\"|!tty=stdin)",
             "delim"          : "input file record delimiter",
             "one-file-system": "block recursion across devices",
             "chase"          : "chase symlinks in recursion",
             "dereference"    : "dereference symlinks for size",
             "apparent-size"  : "instead total ``st_bytes``",
             "inodes"         : "instead total inode count",
             "count-links"    : "count hard links multiple times",
             "exclude"        : "exclude paths matching pattern(s)",
             "exclude-from"   : "exclude all pattern(s) in named file",
             "bytes"          : "like --block-size=1",
             "kilo"           : "like --block-size=1[Kk] (*DEFAULT*)",
             "mega"           : "like --block-size=1[Mm]",
             "giga"           : "like --block-size=1[Gg]",
             "tera"           : "like --block-size=1[Tt]",
             "peta"           : "like --block-size=1[Pp]",
             "block-size"     : "units; CAPITAL sfx=metric else binary",
             "summarize"      : "echo only total for each argument",
             "si"             : "-[kmgt] mean powers of 1000 not 1024",
             "human-readable" : "print sizes in human readable format",
             "total"          : "display a grand total",
             "outEnd"         : "output record terminator",
             "quiet"          : "suppress most OS error messages" })
