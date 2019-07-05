import os, parsecfg, streams, strutils

proc cfToCL*(path: string, subCmdName="", quiet=false,
             noRaise=false): seq[string] =
  ## Drive Nim stdlib parsecfg to get either specific subcommand parameters if
  ## ``subCmdName`` is non-empty or else global command parameters.
  var activeSection = subCmdName.len == 0
  var f = newFileStream(path, fmRead)
  if f == nil:
    if not quiet:
      stderr.write "cannot open: ", path, "\n"
      return
    elif not noRaise: raise newException(IOError, "")
    else: return
  var p: CfgParser
  open(p, f, path)
  while true:
    var e = p.next
    case e.kind
    of cfgEof:
      break
    of cfgSectionStart:
      if subCmdName.len > 0:
        activeSection = e.section == subCmdName
      if e.section.startsWith("include__"):
        let sub = e.section[9..^1]
        result.add cfToCL(if sub == sub.toUpperAscii: getEnv(sub)
                          else: path.parentDir & "/" & sub,
                          subCmdName, quiet, noRaise)
    of cfgKeyValuePair, cfgOption:
      when defined(debugCfToCL):
        echo "key: ", e.key.repr, " val: ", e.value.repr
      if activeSection:
        result.add("--" & e.key & "=" & e.value)
    of cfgError: echo e.msg
  close(p)

proc envToCL*(evarName: string): seq[string] =
  var e = os.getEnv(evarName)
  if e.len == 0:
    return
  let sp = e.parseCmdLine               #See os.parseCmdLine for details
  result = result & sp
  when defined(debugEnvToCL):
    echo "parsed $", varNm, " into: ", sp
