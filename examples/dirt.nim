# NOTE: Needs `devel` / >= 1.4.0 for `HeapQueue[T].find`.
import std/[heapqueue,sets,posix,strformat], cligen,cligen/[dents,posixUt,statx]

proc setMTime*(dfd: cint; path: string; m0, m1: StatxTs;
               verb: File=nil, err=stderr, dryRun=false): int =
  ## Set the file m1)odification time of ``(dfd,path[nmAt..^1])`` only if not
  ## equal to the original ``m0`` times with typical command utility ``verb``,
  ## ``err``, ``dryRun`` parameters, returning if the call must/did occur.
  if m0 == m1: return 0
  result = 1
  let omit = Timespec(tv_sec: 0.Time, tv_nsec: UTIME_OMIT)
  var ftms = [ omit, toTimespec(m1)]
  verb.log &"futimens({dfd}({path}), [OMIT, {$ftms[1]}])\n"
  if not dryRun and futimens(dfd, ftms) != 0:
    err.log &"futimens({dfd}({path}): {strerror(errno)}\n"

proc dirt*(roots: seq[string], verbose=false, quiet=false, dryRun=false,
           prune: seq[string] = @[], xdev=false): int =
  ## Set mtimes of dirs under ``roots`` to mtime of its newest kid.  This makes
  ## directory mtimes "represent" content age at the expense of erasing evidence
  ## of change which can be nice for time-sorted ls in some archival file areas.
  if roots.len == 0:  # For safety, do nothing if user specifies empty `paths`
    return
  let prune = toHashSet(prune)
  let verb = if dryRun or verbose: stdout else: nil
  let err  = if quiet: nil else: stderr
  var n    = 0
  for root in roots:
    var dirs = @[initHeapQueue[int64]()]      # HeapQueue.pop is *MINIMUM*
    forPath(root, 0, lstats=true, false, xdev, false, err,
            depth, path, nmAt, ino, dt, lSt, dfd, dst, did):
      if dt != DT_LNK:                        # Always:
        dirs[^1].push -toInt64(lSt.stx_mtime) #   Track max age
    do:                                       # Pre-recurse:
      if path[nmAt..^1] in prune:
        verb.log &"pruning at: {path}\n"
        discard dirs[^1].pop
        continue
      dirs.add initHeapQueue[int64]()         #   Add new queue for kid
      let dmt = lSt.stx_mtime                 #   Save old mtime
    do:                                       # Post-recurse:
      if dirs.len > 0:
        if dirs[^1].len > 0:                  #   Deepest queue non-empty
          let kidTm = dirs[^1].pop            #   Get & use max kid time stamp
          n += setMTime(dfd, path, dmt, toStatxTs(-kidTm), verb, err, dryRun)
          if dirs.len > 1:                    #   ASSUME setMTime SUCCEEDS
            dirs[^2].del  dirs[^2].find(-toInt64(dmt)) #XXX BST/BTreeQ 4big dirs
            dirs[^2].push kidTm               #   reflect dmt -> kidTm in parent
        discard dirs.pop                      #   discard kid queue
    do: recFailDefault("dirt", path)          # Cannot recurse
  return min(n, 255)

when isMainModule:
  dispatch(dirt, short = { "dry-run": 'n' }, help = {
             "verbose": "print `utimes` calls as they happen",
             "quiet"  : "suppress most OS error messages",
             "dry-run": "only print what system calls are needed",
             "prune"  : "prune exactly matching paths from recursion",
             "xdev"   : "block recursion across device boundaries" })
