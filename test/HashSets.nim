import sets
when not declared(initHashSet):
  proc toHashSet[A](keys: openArray[A]): HashSet[A] = toSet[A](keys)
  proc initHashSet[A](initialSize=64): HashSet[A] = initSet[A](initialSize)

type Color = enum red, green, blue

proc demo(args: seq[string],
          i1: HashSet[int8]   = initHashSet[int8]() ,
          I1: HashSet[int8]   = toHashSet([2'i8, 3]),
          i2: HashSet[int16]  = initHashSet[int16](),
          I2: HashSet[int16]  = toHashSet([4'i16,5]),
          u1: HashSet[uint8]  = initHashSet[uint8](),
          U1: HashSet[uint8]  = toHashSet([6'u8, 7]),
          u2: HashSet[uint16] = initHashSet[uint16](),
          U2: HashSet[uint16] = toHashSet([8'u16,9]),
          e : HashSet[Color]  = initHashSet[Color](),
          E : HashSet[Color]  = toHashSet([red,blue])): int =
  ## demo entry point with parameters of all basic types.
  echo "i1: ", i1, " I1: ", I1
  echo "i2: ", i2, " I2: ", I2
  echo "u1: ", u1, " U1: ", U1
  echo "u2: ", u2, " U2: ", U2
  echo "e: " , e , " E: " , E
  for i, arg in args: echo "positional[", i, "]: ", arg
  return 42

when isMainModule:
  import cligen; dispatch(demo)
