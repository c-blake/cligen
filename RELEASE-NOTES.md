RELEASE NOTES
=============

Version: 0.9.9
--------------

There are several major breaking changes:

 1. ``argParse`` templates have a new parameter, the default value for
    the proc parameter being parsed.  So, now they get (current as a var,
    default as a value, input as a string).  Anyone defining argParse
    will have to update their signatures.
   
 2. ``argHelp`` templates have a new final parameter ``rq`` that is 0 if
     a parameter is optional, and non-zero if it is ReQuired.

These two changes are both related to significant behavior changes.  1) relates
to a change in how boolean parameters are handled.  They no longer toggle back
and forth forever, but rather now only flip from their default to its opposite.
See https://github.com/c-blake/cligen/issues/16
There could be other types/situations for which knowing the default is useful.

2) relates to a complete shift in the syntax for mandatory parameters to be
keyed just as optional parameters are, but to exit with an error when not all
are given by a command user.  See https://github.com/c-blake/cligen/issues/20
This is more consistent syntax, has more consistent help text in the usage
message and is also more informative to the user as to what they did wrong.
