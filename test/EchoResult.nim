import cligen
when NimVersion <= "0.19.4":
  import editDistance
else:
  import std/editDistance
dispatch(editDistanceAscii, echoResult=true, requireSeparator=true)
