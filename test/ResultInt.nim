import cligen
when (NimMajor,NimMinor,NimPatch) <= (0,19,8):
  import editDistance
else:
  import std/editDistance

clCfg.version = "1.0"
dispatchGen(editDistanceAscii)

try:
  echo "edit distance is ", dispatcheditDistanceAscii()
except HelpOnly, VersionOnly:
  quit(0)
except ParseError:
  quit(1)
