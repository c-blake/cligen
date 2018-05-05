import sets

type Color = enum red, green, blue

proc demo(args: seq[string],
          i1: HashSet[int8]  =initSet[int8]()  , I1: HashSet[int8]   = toSet([ 3'i8, 4'i8 ]),
          i2: HashSet[int16] =initSet[int16]() , I2: HashSet[int16]  = toSet([ 5'i16, 6'i16 ]),
          u1: HashSet[uint8] =initSet[uint8]() , U1: HashSet[uint8]  = toSet([ 13'u8, 14'u8 ]),
          u2: HashSet[uint16]=initSet[uint16](), U2: HashSet[uint16] = toSet([ 15'u16, 16'u16 ]),
          e : HashSet[Color] =initSet[Color]() , E : HashSet[Color]  = toSet([ red, green, blue ])
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
