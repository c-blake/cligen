proc demo(args: seq[string],
          bl: seq[bool]    = @[ ], Bl: seq[bool]    = @[ false, true ],
          s:  seq[string]  = @[ ], S:  seq[string]  = @[ "ho", "hey" ],
          i:  seq[int]     = @[ ], I:  seq[int]     = @[ 1, 2 ],
          i1: seq[int8]    = @[ ], I1: seq[int8]    = @[ 3'i8, 4'i8 ],
          i2: seq[int16]   = @[ ], I2: seq[int16]   = @[ 5'i16, 6'i16 ],
          i4: seq[int32]   = @[ ], I4: seq[int32]   = @[ 7'i32, 8'i32 ],
          i8: seq[int64]   = @[ ], I8: seq[int64]   = @[ 9'i64, 10'i64 ],
          u:  seq[uint]    = @[ ], U:  seq[uint]    = @[ 11'u, 12'u ],
          u1: seq[uint8]   = @[ ], U1: seq[uint8]   = @[ 13'u8, 14'u8 ],
          u2: seq[uint16]  = @[ ], U2: seq[uint16]  = @[ 15'u16, 16'u16 ],
          u4: seq[uint32]  = @[ ], U4: seq[uint32]  = @[ 17'u32, 18'u32 ],
          u8: seq[uint64]  = @[ ], U8: seq[uint64]  = @[ 19'u64, 20'u64 ],
          f4: seq[float32] = @[ ], F4: seq[float32] = @[ 23'f32, 24'f32 ],
          f8: seq[float64] = @[ ], F8: seq[float64] = @[ 25'f64, 26'f64 ]
          ): int =
  ## demo entry point with parameters of all basic types.
  echo "bl: ", bl, " Bl: ", Bl
  echo "s: " , s , " S: " , S
  echo "i:  ", i , " I:  ", I
  echo "i1: ", i1, " I1: ", I1
  echo "i2: ", i2, " I2: ", I2
  echo "i4: ", i4, " I4: ", I4
  echo "i8: ", i8, " I8: ", I8
  echo "u:  ", u , " U:  ", U
  echo "u1: ", u1, " U1: ", U1
  echo "u2: ", u2, " U2: ", U2
  echo "u4: ", u4, " U4: ", U4
  echo "u8: ", u8, " U8: ", U8
  echo "f4: ", f4, " F4: ", F4
  echo "f8: ", f8, " F8: ", F8
  for i, arg in args: echo "positional[", i, "]: ", arg
  return 42

when isMainModule:
  import cligen; dispatch(demo)
