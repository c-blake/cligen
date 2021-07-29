import std/[strformat, posix], cligen, cligen/[dents, posixUt, statx]

proc rr*(roots: seq[string], xdev=false, eof0=false): int =
  ## Like rm -rf but a bit faster.  Does nothing if no ``roots`` specified.
  if roots.len == 0: return
  var dfds: seq[cint]
  for root in roots:
    forPath(root, 0, false, false, xdev, eof0, stderr,
            depth, path, nmAt, ino, dt, lst, dfd, dst, did):
      if dt != DT_DIR:
        if unlinkat(dfd, path[nmAt..^1].cstring, 0) != 0:
          stderr.log &"rr({path}): {strerror(errno)}\n"
      elif dfds.len > 0 and dfds[^1] == dfd: discard
      else: dfds.add dfd
    do: discard                   # Pre-recurse
    do:                           # Post-recurse (dt == DT_DIR guaranteed)
      if unlinkat(dfds.pop, path[nmAt..^1].cstring, AT_REMOVEDIR) != 0:
        stderr.log &"rr({path}): {strerror(errno)}\n"
        # Future dir-unlinks are doomed to fail ENOTEMPTY except if ENOENT here
        # IF racing other unlinker(s).  quit here forfeits any such races.
        quit(1)
    do: recFailDefault("rr", path)  # Cannot recurse
  return 0

when isMainModule:
  dispatch(rr, help = { "xdev" : "block recursion across device boundaries" })
