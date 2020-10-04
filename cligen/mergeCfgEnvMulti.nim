import std/[os, strutils], cligen/cfUt

{.push warning[ProveField]: off.}
proc mergeParams(cmdNames: seq[string],
                 cmdLine=os.commandLineParams()): seq[string] =
  ## This is an include file to provide query & merge of alternate sources for
  ## command-line parameters according to common conventions.  First it looks
  ## for and parses a ${PROG_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}}/PROG
  ## config file where PROG=cmdNames[0] (uppercase in env vars, but samecase
  ## otherwise).  Then it looks for a $PROG environment variables ('_' extended
  ## for multi-commands, e.g. $PROG_SUBCMD).  Finally, it appends the passed
  ## ``cmdLine`` (usually command-line-entered parameters or @["--help"]).
  when defined(debugMergeParams):
    echo "mergeParams got cmdNames: ", cmdNames, " cmdLine:", cmdLine
  if cmdNames.len < 2:
    return cmdLine
  var cfPath = os.getEnv(strutils.toUpperAscii(cmdNames[0]) & "_CONFIG")
  if cfPath.len == 0:
    cfPath = os.getConfigDir() & cmdNames[0] & "/config"
    if not fileExists(cfPath):
      cfPath = cfPath[0..^8]
  if fileExists(cfPath):
    result.add cfToCL(cfPath, if cmdNames.len > 1: cmdNames[1] else: "")
  result.add envToCL(strutils.toUpperAscii(strutils.join(cmdNames, "_")))
  result.add cmdLine
{.pop.}
