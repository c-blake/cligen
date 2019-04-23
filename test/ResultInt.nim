import cligen, editDistance

dispatchGen(editDistanceAscii, version = ("version", "1.0"))

try:
  echo "edit distance is ", dispatchEditDistanceAscii()
except HelpOnly, VersionOnly:
  quit(0)
except ParseError:
  quit(1)
