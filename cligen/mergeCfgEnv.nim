{.warning[Uninit]:off, warning[ProveInit]:off.} # Should be verbosity:2 not 1
{.push hint[Performance]: off.}
{.push warning[ProveField]: off.}

when not declared(os.joinPath): from std/os import commandLineParams, getEnv,
                                                   getConfigDir, fileExists, `/`
when not declared(strutils.split): from std/strutils import toUpperAscii
when not declared(cfToCL):         from cligen/cfUt  import cfToCL, envToCL

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
  if cmdNames.len < 1:
    return cmdLine
  var cfPath = os.getEnv(strutils.toUpperAscii(cmdNames[0]) & "_CONFIG")
  if cfPath.len == 0:
    cfPath = os.getConfigDir() / cmdNames[0] / "config"
    if not os.fileExists(cfPath):
      cfPath = cfPath[0..^8]
  if os.fileExists(cfPath):
    result.add cfToCL(cfPath, if cmdNames.len > 1: cmdNames[1] else: "")
  result.add envToCL(strutils.toUpperAscii(strutils.join(cmdNames, "_")))
  result.add cmdLine
  when defined(debugMergeParams): echo "mergeParams returned: ", result
{.pop.}
# Leave hint[Performance]=off as this seems required to avoid warnings.
