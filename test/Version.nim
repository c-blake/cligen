proc demo(alpha: int=1, item: string="hi", args: seq[string]): int =
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  echo "alpha:", alpha, " item:", item
  for i, arg in args: echo "positional[", i, "]: ", arg
  return 42

when isMainModule:
  import cligen; include cligen/mergeCfgEnv

  when defined(versionGit):
    const vsn = staticExec "git describe --tags HEAD"
    clCfg.version = vsn
    dispatch(demo)
  elif defined(versionNimble):
    const nimbleFile = staticRead "../cligen.nimble"  #Use YOURPKG not cligen
    clCfg.version = nimbleFile.fromNimble "version"
    dispatch(demo)
  else:
    clCfg.version = "1.5"
    when defined(versionShort):
      dispatch(demo, short = { "version": 'V' })
    else:
      dispatch(demo, cmdName="Version",
               help = { "version": "Print Version & Exit 0" })
