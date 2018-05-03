RELEASE NOTES
=============

Version: 0.9.9
--------------

There are several major breaking changes and feature additions:

 1. A complete shift in the syntax for mandatory parameters.  They are now
    entered just as optional parameters are.  Programs exit with informative
    errors when not all are given by a command user.  This is more consistent
    syntax, has more consistent help text in the usage message and is easier
    on balance for command users.  For discussion, see
    https://github.com/c-blake/cligen/issues/20
    This is the biggest command-user visible change.

 2. ``argParse`` and ``argHelp`` are now `proc`s taking var parameters to
    assign, not templates and both take a new ``argcvtParams`` object to
    hopefully never have to change the signature of these symbols again.
    Anyone defining ``argParse``/``argHelp`` will have to update their code.

    These should probably always have been procs with var parameters.
    Doing so now was motivated to implemenet generic support of collections
    (set and seq) of any enum type.

 3. ``argHelp`` is simplified.  It needs only to return a len 3 `seq` - the
    keys column (usually just a.argKeys), the type column and the default
    value column.  See `argcvt` for examples.

 4. ``parseopt3`` can now capture the separator text used by CLI users which
    includes any trailing characters in `opChars`.  ``argParse`` can access
    such text to implement things like ``--mySeq+=foo,bar``.

 5. Boolean parameters no longer toggle back and forth forever by default.
    Rather now only flip from *their default to its opposite*.  There could be
    other types/situations for which knowing the default is useful and argParse
    in general has access to the triple (current, default, new as a string).
    For discussion see https://github.com/c-blake/cligen/issues/16 

 6. ``enum`` types are supported generically.

 7. ``seq[T]`` and ``set[T]`` are supported generically.  I.e., if there is an
    ``argParse`` and ``argHelp`` for a new type ``T`` then `seq`s and `set`s
    containing that type are automatically supported.  `argcvt` documentation
    describes delimiting syntax for aggregate/collection types.
