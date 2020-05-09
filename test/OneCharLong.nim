# Check that auto-assigned short parameter does not collide
# with unabbreviated long but single char parameter.

proc test(sp = ""; sl = ""; s = "") =
   discard

when isMainModule:
  import cligen; dispatch(test)                       # works
# import cligen; dispatch(test, short = {"s": '\0'})  # works
# import cligen; dispatch(test, short = {"s": 'y'})   # works
# import cligen; dispatch(test, short = {"s": 'y', "sp": 's'}) # FAILS
#
# The last commented out line *could* work, but this is hard to support due
# to combined `of` branch in case `pId`.kind of cmdLongOption, cmdShortOption:
# in generated parsers.  Since the 's'/"s" keys collide as strings only being
# disambiguated via the type of option being used, supporting this entails a
# major rewrite or overhaul of the core generated parser.
