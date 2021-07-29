import posix/inotify, std/posix, cligen, cligen/[sysUt, posixUt]

type Event* = enum
  inAccess    ="access"   , inAttrib ="attrib"    , inModify    ="modify"      ,
  inOpen      ="open"     , inCloseWr="closeWrite", inCloseNoWr ="closeNoWrite",
  inMovedFrom ="movedFrom", inMovedTo="movedTo"   , inMoveSelf  ="moveSelf"    ,
  inCreate    ="create"   , inDelete ="delete"    , inDeleteSelf="deleteSelf"

proc mask(es: set[Event]): uint32 =
  template `|=`(r, f) = r = r or f
  for e in es:
    case e
    of inAccess    : result |= IN_ACCESS    
    of inAttrib    : result |= IN_ATTRIB    
    of inModify    : result |= IN_MODIFY    
    of inOpen      : result |= IN_OPEN      
    of inCloseWr   : result |= IN_CLOSE_WRITE
    of inCloseNoWr : result |= IN_CLOSE_NOWRITE
    of inMovedFrom : result |= IN_MOVED_FROM 
    of inMovedTo   : result |= IN_MOVED_TO   
    of inMoveSelf  : result |= IN_MOVE_SELF  
    of inCreate    : result |= IN_CREATE    
    of inDelete    : result |= IN_DELETE    
    of inDeleteSelf: result |= IN_DELETE_SELF

iterator dqueue*(dir: string; events={inMovedTo, inCloseWr}):
    tuple[name: ptr char; len: int] =
  ## Set up event watches on dir & forever yield NUL-terminated (ptr char,len).
  if chdir(dir) == -1:
    raise newException(OSError, "chdir(\"" & dir & "\")")
  let fd = cint(inotify_init())
  if fd == -1:
    raise newException(OSError, "inotify_init")
  if inotify_add_watch(fd, dir, events.mask or IN_ONLYDIR) == -1:
    raise newException(OSError, "inotify_add_watch")
  var evs = newSeq[byte](8192)
  while (let n = read(fd, evs[0].addr, 8192); n) > 0:
    for ev in inotify_events(evs[0].addr, n):
      yield (ev[].name.addr, int(ev[].len))

when isMainModule:
  proc dirq(events={inMovedTo, inCloseWr}; dir="."; wait=false;
            cmdPrefix: seq[string]): int =
    ## chdir(*dir*) & wait for *events* to occur on it; then run *cmdPrefix*
    ## **NAME** where **NAME** is the filename (not full path) delivered with
    ## the event.  Default events are any writable fd-close on files in *dir* or
    ## rename into *dir* (usually signaling **NAME** is ready as an input file).
    let n   = cmdPrefix.len                     # index of a new last slot
    let cmd = allocCStringArray(cmdPrefix & "") # setup ready-to-exec buffer
    if not wait:
      signal(SIGCHLD, reapAnyKids)              # Block zombies
    for (name, nmLen) in dqueue(dir, events):
      if nmLen > 0 or name != nil:
        cmd[n] = name.cstring                   # Poke ptr char into slot and..
        discard cmd.system(wait)                #..run command, maybe in bkgd

  dispatch(dirq, help = { "events": "inotify event types to use; " &
                                    "Giving \"x\" lists all",
                          "dir"   : "directory to watch",
                          "wait"  : "wait4(kid) until re-launch" })
