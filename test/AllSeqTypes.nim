proc demo(args: seq[string],
#         bl: seq[bool] = false,
          st: seq[string] = @[ ],
#         i: seq[int] = 1,
#         i1: seq[int8] = 2,
#         i2: seq[int16] = 3,
#         i4: seq[int32] = 4,
#         i8: seq[int64] = 5,
#         u: seq[uint] = 6,
#         u1: seq[uint8] = 7,
#         u2: seq[uint16] = 8,
#         u4: seq[uint32] = 9,
#         u8: seq[uint64] = 10,
#         f: seq[float] = 11,
#         f4: seq[float32] = 12,
#         r8: seq[float64] = 13
          ): int =
  ## demo entry point with parameters of all basic types.
# echo "bl: ", bl
  echo "st: ", st
# echo "i : ", i
# echo "i1: ", i1
# echo "i2: ", i2
# echo "i4: ", i4
# echo "i8: ", i8
# echo "u : ", u
# echo "u1: ", u1
# echo "u2: ", u2
# echo "u4: ", u4
# echo "u8: ", u8
# echo "f : ", f
# echo "f4: ", f4
# echo "r8: ", r8
  for i, arg in args: echo "positional[", i, "]: ", repr(arg)
  return 42

when isMainModule:
  import cligen, argSeqDPSV
  dispatch(demo)
