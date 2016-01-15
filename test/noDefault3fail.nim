proc demo(alpha=1, verb: bool, files: seq[string] = @[]): int =
  ## demo entry point with varied, meaningless parameters.
  echo "alpha:", alpha, " verb:", verb, " files:", repr(files)
  return 42

when isMainModule:
  import cligen
  dispatch(demo)
