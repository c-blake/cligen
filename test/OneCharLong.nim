# Check that auto-assigned short parameter does not collide
# with unabbreviated long but single char parameter.

proc test(sp = ""; sl = ""; s = "") =
   discard

when isMainModule:
  import cligen; dispatch(test)                       # works
# import cligen; dispatch(test, short = {"s": '\0'})  # works
# import cligen; dispatch(test, short = {"s": 'y'})   # works
# import cligen; dispatch(test, short = {"s": 's'})   # works
# import cligen; dispatch(test, short = {"s": 'y', "sp": 's'}) # FAILS
#
# The last commented out line *could* work, but this is hard to support due
# to combined `of` branch in case `pId`.kind of cmdLongOption, cmdShortOption:
# in generated parsers.  Since the 's'/"s" keys collide as strings only being
# disambiguated via the type of option being used.  Could do this with large
# if-else block or parseopt3-namespacing short options, but maybe fully general
# is a bad idea here?  Bool short-opts are "combining".  So full ctrl is nice,
# but having -s mean something totally different than --s is also confusing.
