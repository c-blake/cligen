proc demo(alpha: int=1, item: string="hi", args: seq[string]): int =
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  echo "alpha:", alpha, " item:", repr(item)
  for i, arg in args: echo "positional[", i, "]: ", repr(arg)
  return 42

when isMainModule:
  import cligen
  when defined(versionGit):
    const vsn = staticExec "git log -1 | head -n1"
    dispatch(demo, version = ("version", vsn))
  elif defined(versionShort):
    let vsn = "1.5"
    dispatch(demo, version = ("version", vsn), short = { "version": 'V' })
  else:
    dispatch(demo, version = ("version", "1.0"))
