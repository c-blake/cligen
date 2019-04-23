import cligen
when NimVersion <= "0.19.4":
  import editDistance
else:
  import std/editDistance

dispatchGen(editDistanceAscii, version = ("version", "1.0"))

try:
  echo "edit distance is ", dispatchEditDistanceAscii()
except HelpOnly, VersionOnly:
  quit(0)
except ParseError:
  quit(1)
