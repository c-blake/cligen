proc demo(usage=1, cmdline="bad name", getopt="ho", args: seq[string]): int =
  ## This tests if things work when a wrapped user-proc uses identifiers also
  ## used in our generated dispatch proc.
  echo "usage:", usage, " cmdline:", cmdline, " getopt:", getopt
  for i, arg in args: echo "positional[", i, "]: ", arg
  return 42

when isMainModule:
  import cligen
  dispatch(demo)
