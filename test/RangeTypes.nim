type
  Dice = range[1 .. 6]
  QuasiInt = range[int64(int32.low) .. int64.high]

proc demoInt(nat = 0.Natural,
             pos = Positive(1),
             dice: Dice = 6,
             delta: range[-5 .. +5] = 0,
             score = range[0'u8 .. 100'u8] 0,
             q: QuasiInt = -1) =
  echo nat, ' ', pos, ' ', dice, ' ', delta, ' ', score.uint8, ' ', q

when (NimMajor, NimMinor) >= (0, 20):
  type Angle = range[0.0 .. 360.0]

  proc demoFlt(angle: Angle = 90.0,
               dist: range[-1.45 .. 1.45] = 1.0,
               f32: range[-3.2'f32 .. 3.2'f32] = 0'f32,
               f64: range[-6.4'f64 .. 6.4'f64] = 0'f64) =
    echo angle, ' ', dist, ' ', f32, ' ', f64

when isMainModule:
  import cligen

  when (NimMajor, NimMinor) >= (0, 20):
    dispatchMulti([demoInt, cmdName = "demo-int"],
                  [demoFlt, cmdName = "demo-flt"])
  else:
    dispatchMulti([demoInt, cmdName = "demo-int"])
