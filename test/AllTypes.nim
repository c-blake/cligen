proc demo(aa: bool = false,
          bb: string = "hi",
          cc: cstring = "ho",
          dd: char = 'X',
          ee: int = 1,
          ff: int8 = 2,
          gg: int16 = 3,
          hh: int32 = 4,
          ii: int64 = 5,
          jj: uint = 6,
          kk: uint8 = 7,
          ll: uint16 = 8,
          mm: uint32 = 9,
          nn: uint64 = 10,
          oo: float = 11,
          pp: float32 = 12,
          qq: float64 = 13,
          args: seq[string]): int =
  ## demo entry point with parameters of all basic types.
  echo "aa: ", aa
  echo "bb: ", bb
  echo "cc: ", cc
  echo "dd: ", dd
  echo "ee: ", ee
  echo "ff: ", ff
  echo "gg: ", gg
  echo "hh: ", hh
  echo "ii: ", ii
  echo "jj: ", jj
  echo "kk: ", kk
  echo "ll: ", ll
  echo "mm: ", mm
  echo "nn: ", nn
  echo "oo: ", oo
  echo "pp: ", pp
  echo "qq: ", qq
  for i, arg in args: echo "positional[", i, "]: ", arg
  return 42

when isMainModule: import cligen; dispatch(demo, short={"help": '?'})
