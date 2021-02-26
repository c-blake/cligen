type
  Dice = range[1 .. 6]
  QuasiInt = range[int64(int32.low) .. int64.high]

proc demo(nat = 0.Natural,
          pos = Positive(1),
          dice: Dice = 6,
          delta: range[-5 .. +5] = 0,
          score = range[0'u8 .. 100'u8] 0,
          q: QuasiInt = -1) =
  echo nat, ' ', pos, ' ', dice, ' ', delta, ' ', score.uint8, ' ', q

when isMainModule:
  import cligen; dispatch(demo)
