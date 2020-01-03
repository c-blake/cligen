proc demo(u=1, c="bad name", g="ho", b: seq[string]): int =
  ## This tests if single character parameters work as expected
  echo "u:", u, " c:", c, " g:", g
  for i, a in b: echo "positional[", i, "]: ", a
  return 42

when isMainModule:
  import cligen
  dispatch(demo)
