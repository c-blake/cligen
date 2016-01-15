proc demo(alpha=1, verb=false, flag: bool): int =
  ## demo entry point with varied, meaningless parameters.
  echo "alpha:", alpha, " verb:", verb, " flag:", repr(flag)
  return 42

when isMainModule:
  import cligen
  dispatch(demo)
