import os, parsecfg, strutils, streams

proc mergeParams(cmdNames: seq[string],
                 cmdLine=os.commandLineParams()): seq[string] =
  ## This is an include file to provide query & merge of alternate sources for
  ## command-line parameters according to common conventions.  First it looks
  ## for and parses a ${PROG_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}}/PROG
  ## config file where PROG=cmdNames[0] uppercase in env vars, but samecase
  ## otherwise.  Then it looks for a $PROG environment variables ('_' extended
  ## for multi-commands, e.g. $PROG_SUBCMD).  Finally, it appends the passed
  ## cmdLine (which is usually command-line entered parameters or @["--help"]).
# stderr.write "got cmdNames: ", repr(cmdNames), "\n"
  var cfPath = os.getEnv(strutils.toUpperAscii(cmdNames[0]))
  if cfPath.len == 0: cfPath = os.getConfigDir() & cmdNames[0]
  if existsFile(cfPath):
    var f = newFileStream(cfPath, fmRead)
    var activeSection = cmdNames.len == 1
    if f != nil:
      var p: CfgParser
      open(p, f, cfPath)
      while true:
        var e = p.next
        case e.kind
        of cfgEof: break
        of cfgSectionStart:
          activeSection = cmdNames.len > 1 and e.section == cmdNames[1]
        of cfgKeyValuePair:
          if activeSection: result.add("--" & e.key & "=" & e.value)
        of cfgOption: discard
        of cfgError: echo e.msg
      close(p)
    else:
      stderr.write "cannot open: ", cfPath, "\n"
  let e = os.getEnv(strutils.toUpperAscii(strutils.join(cmdNames, "_")))
  if e.len > 0:
    result = result & parseCmdLine(e)                      #See os.parseCmdLine
  result = result & cmdLine
