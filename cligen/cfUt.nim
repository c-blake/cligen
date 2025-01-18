import std/[os, parsecfg, streams, strutils]
when not declared(stderr): import std/syncio

proc cfToCL*(path: string, subCmdName="", quiet=false,
             noRaise=false, activeSec=false): seq[string] =
  ## Drive Nim stdlib parsecfg to get either specific subcommand parameters if
  ## ``subCmdName`` is non-empty or else global command parameters.
  var activeSection = subCmdName.len == 0 or activeSec
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
      if e.section.startsWith("include__"):
        let sub = e.section[9..^1]
        let subs = sub.split("__") # Allow include__VAR_NAME__DEFAULT[__..IGNOR]
        let subp = if subs.len>0 and subs[0] == subs[0].toUpperAscii:
                     getEnv(subs[0], if subs.len>1: subs[1] else: "") else: sub
        result.add cfToCL(if subp.startsWith("/"): subp
                          else: path.parentDir & "/" & subp,
                          subCmdName, quiet, noRaise, activeSection)
      elif subCmdName.len > 0:
        activeSection = e.section == subCmdName
    of cfgKeyValuePair, cfgOption:
      when defined(debugCfToCL):
        echo "key: \"", e.key, "\" val: \"", e.value, "\""
      if activeSection:
        result.add("--" & e.key & "=" & e.value)
    of cfgError: echo e.msg
  close(p)

proc envToCL*(evarName: string): seq[string] =
  let e = os.getEnv(evarName)
  if e.len == 0:
    return
  try: result = e.parseCmdLine # See os.parseCmdLine for details
  except CatchableError: stderr.write "ignoring bad evarName $", evarName, "\n"
  when defined(debugEnvToCL):
    echo "parsed $", varNm, " into: ", result
