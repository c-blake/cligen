# This tests if things work if the wrapped user-proc uses identifiers also in
# our generated dispatch proc.  Should be fine as long as no imports pull in a
# name like "disapatcherFoo".

proc demo(usage=1, cmdline="bad name", getopt="ho", args: seq[string]): int =
  echo "usage:", usage, " cmdline:", repr(cmdline), " getopt:", getopt
  for i, arg in args: echo "positional[", i, "]: ", repr(arg)
  return 42

when isMainModule:
  import cligen
  dispatch(demo)
