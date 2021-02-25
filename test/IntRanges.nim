type Dice = range[1 .. 6]

proc demo(nat = 0.Natural,
          pos = Positive(1),
          dice: Dice = 6,
          delta: range[-5 .. 5] = 0) =
  echo nat, ' ', pos, ' ', dice, ' ', delta

when isMainModule:
  import cligen; dispatch(demo)
