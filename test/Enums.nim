type Color = enum re_d, green = "gre-en", blue

proc demo(c: Color, bg=red, fg= @[green], curs={blue}, x=0, args: seq[string]) =
  ## demo entry point with varied, meaningless parameters.
  echo "bg: ", bg, " fg: ", fg, " curs: ", curs
  for i, arg in args: echo "positional[", i, "]: ", arg

when isMainModule:
  import cligen
  dispatch(demo,
           help = { "c"   : "primary color",
#                   "bg"  : "background color",
                    "fg"  : "foreround colors",
                    "curs": "cursor colors" })
