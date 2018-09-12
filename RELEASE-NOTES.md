RELEASE NOTES
=============

Version: 0.9.14
---------------
    Add range checking for all numeric types to argParseHelpNum

    Adapt code to new Nim nil world order.  One visible consequence is that
    passing empty values to string/cstring type parameters is allowed/easy.

Version: 0.9.13
---------------
    Add ``version`` parameter to ``dispatchGen`` and ``dispatch``.

    Send "--help" and "--version"-type output to ``stdout`` not ``stderr`` for
    easier shell re-direction.

Version: 0.9.12
---------------
    Rename to be more NEP1 compliant. User-visible renames should be limited to:
      argcvtParams         -> ArgcvtParams
      argcvtParams.Help    -> ArgcvtParams.help
      argcvtParams.Delimit -> ArgcvtParams.delimit
      argcvtParams.Mand    -> ArgcvtParams.mand

    Remaining violations are where I disagree with current --nep1:on are:
	HelpOnlyId as an exception
	WideT and T as types
	ERR where I like all caps to shout the id
    I might be persuadable to change the last one, but the first two are very
    much canonical NEP1 that --nep1:on gets wrong.  Until those are fixed, I
    see little point in being perfectly --nep1:on clean. (Also, that rename
    should not cause any user-code to break, unlike the argcvtParams renames.)

Version: 0.9.11
---------------
    Add new ``mandatoryOverride`` parameter to dispatchGen/dispatch for
    situations like --version where it is assumed the proc will exit before
    trying to meaningfully use any mandatory parameters.

Version: 0.9.10
---------------
    Appease nimble structure requirements.  The only breaking change should
    be the need to import cligen/argcvt if you define your own converters.

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

 2. ``argParse`` and ``argHelp`` are now `proc`s taking ``var`` parameters to
    assign, not templates and both take a new ``argcvtParams`` object to
    hopefully never have to change the signature of these symbols again.
    Anyone defining ``argParse``/``argHelp`` will have to update their code.

    These should probably always have been procs with var parameters.  Doing
    so now was motivated to implemenet generic support of collections (``set``
    and ``seq``) of any ``enum`` type.

 3. ``argHelp`` is simplified.  It needs only to return a len 3 `seq` - the
    keys column (usually just ``a.argKeys``), the type column and the default
    value column.  See ``argcvt`` for examples.

 4. ``parseopt3`` can now capture the separator text used by CLI users which
    includes any trailing characters in ``opChars``.  ``argParse`` can access
    such text to implement things like ``--mySeq+=foo,bar``.

 5. Boolean parameters no longer toggle back and forth forever by default. They
    now only flip from *their default to its opposite*.  There could be other
    types/situations for which knowing the default is useful and ``argParse``
    in general has access to the triple (current, default, new as a string).
    For discussion see https://github.com/c-blake/cligen/issues/16 

 6. ``enum`` types are supported generically.

 7. ``seq[T]`` and ``set[T]`` are supported generically.  I.e., if there is an
    ``argParse`` and ``argHelp`` for a new type ``T`` then ``seq`` and ``set``
    containing that type are automatically supported.  ``argcvt`` documentation
    describes delimiting syntax for aggregate/collection types.
