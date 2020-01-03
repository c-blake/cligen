type Color = enum red, green, blue

proc demo(args: seq[string],
          bl: set[bool]    = {}, Bl: set[bool]    = { false, true },
          i1: set[int8]    = {}, I1: set[int8]    = { 3'i8, 4'i8 },
          i2: set[int16]   = {}, I2: set[int16]   = { 5'i16, 6'i16 },
          u1: set[uint8]   = {}, U1: set[uint8]   = { 13'u8, 14'u8 },
          u2: set[uint16]  = {}, U2: set[uint16]  = { 15'u16, 16'u16 },
          e : set[Color]   = {}, E : set[Color]   = { red, green, blue }
          ): int =
  ## demo entry point with parameters of all basic types.
  echo "bl: ", bl, " Bl: ", Bl
  echo "i1: ", i1, " I1: ", I1
  echo "i2: ", i2, " I2: ", I2
  echo "u1: ", u1, " U1: ", U1
  echo "u2: ", u2, " U2: ", U2
  for i, arg in args: echo "positional[", i, "]: ", arg
  return 42

when isMainModule:
  import cligen; dispatch(demo)
