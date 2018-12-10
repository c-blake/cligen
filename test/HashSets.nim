import sets

type Color = enum red, green, blue

proc demo(args: seq[string],
  i1: HashSet[int8]  =initSet[int8]()  , I1: HashSet[int8]   = toSet([2'i8, 3]),
  i2: HashSet[int16] =initSet[int16]() , I2: HashSet[int16]  = toSet([4'i16,5]),
  u1: HashSet[uint8] =initSet[uint8]() , U1: HashSet[uint8]  = toSet([6'u8, 7]),
  u2: HashSet[uint16]=initSet[uint16](), U2: HashSet[uint16] = toSet([8'u16,9]),
  e : HashSet[Color] =initSet[Color]() , E : HashSet[Color]  = toSet([red,blue])
): int =
  ## demo entry point with parameters of all basic types.
  echo "i1: ", i1, " I1: ", I1
  echo "i2: ", i2, " I2: ", I2
  echo "u1: ", u1, " U1: ", U1
  echo "u2: ", u2, " U2: ", U2
  echo "e: " , e , " E: " , E
  for i, arg in args: echo "positional[", i, "]: ", repr(arg)
  return 42

when isMainModule:
  import cligen; dispatch(demo)
