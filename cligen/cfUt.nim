import parsecfg, streams

proc cfToCL*(path: string, subCmdName=""): seq[string] =
  ## Drive Nim stdlib parsecfg to get either specific subcommand parameters if
  ## ``subCmdName`` is non-empty or else global command parameters.
  var activeSection = subCmdName.len == 0
  var f = newFileStream(path, fmRead)
  if f == nil:
    stderr.write "cannot open: ", path, "\n"
    return
  var p: CfgParser
  open(p, f, path)
  while true:
    var e = p.next
    case e.kind
    of cfgEof:
      break
    of cfgSectionStart:
      activeSection = e.section == subCmdName
    of cfgKeyValuePair, cfgOption:
      when defined(debugCfToCL):
        echo "key: ", e.key.repr, " val: ", e.value.repr
      if activeSection:
        result.add("--" & e.key & "=" & e.value)
    of cfgError: echo e.msg
  close(p)
