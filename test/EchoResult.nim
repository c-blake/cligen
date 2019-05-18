import cligen
when NimVersion <= "0.19.8":
  import editDistance
else:
  import std/editDistance
dispatch(editDistanceAscii, echoResult=true)
