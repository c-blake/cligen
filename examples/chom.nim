import std/[posix, strformat], cligen/[dents, posixUt, statx]

proc chom1*(dfd:cint,path:string,nmAt:int, st:Statx, uid=Uid.high, gid=Gid.high,
            dirPerm=0o2775.Mode, filePerm=0o664.Mode, execPerm=0o775.Mode,
            verb: File=nil, err=stderr, dryRun=false): int =
  ## This proc enforces specified {owner, group owner, permissions} for {dirs,
  ## non-dirs/non-executable files, and user-executable files}.
  let nm  = path[nmAt..^1].cstring
  let uid = if uid == Uid.high: st.st_uid else: uid
  let gid = if gid == Gid.high: st.st_gid else: gid
  if st.st_uid != uid or st.st_gid != gid:      #uid/gid mismatch: fchownat
    result.inc
    verb.log &"fchownat({uid}.{gid}, {path})\n"
    if not dryRun and fchownat(dfd, nm, uid, gid, 0) != 0:
      err.log &"fchownat({path}): {strerror(errno)}\n"
      return                                    #skip fchmodat if fchownat fails
  let perm = if S_ISDIR(st.st_mode): dirPerm
             elif (st.st_mode and 0o100) != 0: execPerm
             else: filePerm
  if (st.st_mode and 0o7777) != perm:           #perm mismatch: fchmodat
    result.inc
    verb.log &"fchmodat({perm:#o}, {path})\n"
    if not dryRun and fchmodat(dfd, nm, perm, 0) != 0:
      err.log &"fchmodat({path}): {strerror(errno)}\n"

proc chom*(verbose=false, quiet=false, dryRun=false, recurse=0, chase=false,
           xdev=false, owner="", group="", dirPerm=0o2755.Mode,
           filePerm=0o664.Mode, execPerm=0o775.Mode, paths: seq[string]): int =
  ## This enforces {owner, group owner, permissions} for {dirs, non-executable
  ## other files, and user-executable files}.  This only makes chown/chmod
  ## syscalls when needed, both for speed & not to touch ctime unnecessarily.
  ## It does not handle ACLs, network FS defined access, etc.  Return zero if no
  ## calls are needed.
  if paths.len == 0:     #For safety, do nothing if user specifies empty `paths`
    return 0
  let uid   = if owner.len > 0: getpwnam(owner).pw_uid else: Uid.high
  let gid   = if group.len > 0: getgrnam(group).gr_gid else: Gid.high
  let verb  = if dryRun or verbose: stderr else: nil
  let err   = if quiet: nil else: stderr
  var nCall = 0
  for root in paths:
    forPath(root, recurse, true, chase, xdev, false, stderr,
            depth, path, nmAt, ino, dt, lst, dfd, dst, did):
      if dt==DT_LNK and stat(path.cstring, lst)!=0:  # want st not lst data here
        err.log &"stat({path}): {strerror(errno)}\n" # ..(unless we do `lchown`)
      else:
        nCall += chom1(dfd, path, nmAt, lst, uid, gid, dirPerm, filePerm,
                       execPerm, verb, err, dryRun)
    do: discard                                     # No pre-recurse
    do: discard                                     # No post-recurse
    do: recFailDefault("chom", path)                # cannot recurse
  return min(nCall, 255)

when isMainModule:
  import cligen, cligen/argcvt, parseutils

  proc argParse(dst: var Mode, dfl: Mode, a: var ArgcvtParams): bool =
    return a.val.parseOct(dst) > 0

  proc argHelp(dfl: Mode; a: var ArgcvtParams): seq[string] =
    result = @[ a.argKeys, "Perm", &"{dfl:o}" ]

  dispatch(chom, short = { "dry-run": 'n' }, help = {
             "verbose" : "print chown and chmod calls as they happen",
             "quiet"   : "suppress most OS error messages",
             "dry-run" : "only print what system calls are needed",
             "recurse" : "max recursion depth for any dir in `paths`",
             "chase"   : "follow symbolic links to dirs in recursion",
             "xdev"    : "block recursion across device boundaries",
             "owner"   : "owner to set; may need root; defl=self",
             "group"   : "group owner to set; defl=primaryGid(self)",
             "dirPerm" : "permission mask for dirs",
             "filePerm": "permission mask for files",
             "execPerm": "permission mask for u=x files" })
