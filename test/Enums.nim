type Color = enum red, green, blue

proc demo(bg=red, fgs= @[green], cursors={blue}, x=0, args: seq[string]) =
  ## demo entry point with varied, meaningless parameters.
  echo "bg: ", bg, " fgs: ", fgs, " cursors: ", cursors
  for i, arg in args: echo "positional[", i, "]: ", repr(arg)

when isMainModule:
  import cligen
  dispatch(demo,
           help = { "bg"     : "background color",
                    "fgs"    : "foreround colors",
                    "cursors": "cursor colors" })
