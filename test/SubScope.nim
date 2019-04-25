import cligen

proc sub() =
  proc get(a=1) = discard
  proc put(b=2) = discard
  when defined(cligenSingle):
    dispatch(get)
  else:
    dispatchMulti([get], [put])

sub()
