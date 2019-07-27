RELEASE NOTES
=============

Version: 0.9.38
---------------
    Fix a little bug blocking abbrev(mx>0).

    Move `cmp`, `<=`, `-`(a, b: Timespec) from `statx` to `posixUt`.

    cligen/[statx, magic] made somewhat autoconfiguring. (magic could probably
    use more paths.  PRs welcome.)

Version: 0.9.37
---------------
  Add cligen/trie.nim.  Use match routine in abbrev.nim to change compression
  levels and add two new levels. Now the full map is:
    -2 shortest prefix
    -3 shortest suffix
    -4 shortest of either locally (or, upon any collision, shortest global avg)
    -5 shortest any-spot-1-star location
    -6 shortest 2-star pattern if shorter than 1-star
  and it probably won't change (except to maybe grow -7/3-star, -8/4-star,..)

  Also fixed a bug in parseopt3.nim which wasn't normalizing options for bool
  params correctly. (There still might be some issues in mixed abbreviated and
  in need of normalization cases.)

Version: 0.9.35
---------------
  Simplify usage of abbrev with Abbrev type. Generalize to have locally varying
  abbreviations (just unique prefix, suffix, or globally/locally shortest of
  either right now).

  Add Ternary Search Tree cligen/tern.nim and use in cligen/abbrev.nim, fixing
  bug in abbrevation modes -2..-5 in the presence of non-unique prefix strings.
  Name the routines [PS]fx**Pat**(s) to be clear it's a more well-defined answer
  than just unique prefix strings.

Version: 0.9.33,34
------------------
  Add abbrev, parseAbbrev, uniqueAbs, smallestMaxSTUnique to new cligen/abbrev.

Version: 0.9.32
---------------
  For single-dispatch, add a system so that CL users can define aliases (named
  bundles of CL args).  Alias definitions make sense in earlier `mergeParams`s
  sources such as config files or environment variables.  Later on in the
  command parameters they can reference them with a different CL option.  See
  `test/UserAliases.nim` and `test/UserAliases.cf` for an example.  Also add
  `textUt.match` and use it in the new alias system.

  Do not auto word wrap help text for a parameter if the help text contains any
  newlines. [ Note this extends the existing heuristic of considering the main
  doc comment "pre-formatted" if it has 2-or more "\n " substrings and that
  pre-formatted text is less adaptable to run-time terminal width. ]

  Add a way for `initFromCL` to ignore all fields after a given one.  The first
  (but not necessarily only) member of `suppress = @[ first, ... ]` has to have
  the special spelling `suppress = @[ "ALL AFTER myIdent" ]` where `myIdent` is
  replaced by the final field to include in the initializer wrapped as cmdLine.
  {I'd also have liked a rule more like private fields, but didn't see an easy
  way to tell private from public/export-marked fields in `getTypeImpl` output.}

  Add several things to cligen/ helper libraries for building command-line
  utilities like `tab`, `humanUt`, `statx`, and `magic`.

Version: 0.9.31
---------------
  Fix bug where `cligen/mergeCfgEnv.nim` doc comment (and README.md) had said
  `$CMD_CONFIG` but the proc logic only used `$CMD`.  This is breaking for users
  only if they were relying on the old broken/non-standard behavior to point to
  some non-standard config file location.

  Add well-commented single- and multi-dispatch config file examples for people
  using `cligen/mergeCfgEnv`.

  Fix bug where `--v` would not auto-lengthen to `--version`.

  Added more general `fromNimble(nd, field)`.  Deprecated `versionFromNimble`.

  Added a new file `cligen/helpTmpls.nim` to distribute a library of any
  user-suggested `clUse`/`clMultiUse` definitions.

  `dispatchMulti(["multi"])` brackets now properly pass through `dispatchGen`
  keyword arguments.  Additionally, `doc` & `usage` in that `"multi"` slot are
  re-purposed for the top-level help of the multi-command.  See discussion
  here for background:
    https://github.com/c-blake/cligen/issues/107

  Introductory "pre-Usage" summary text is now taken from the first paragraph
  of the doc comment of the module calling `dispatchMulti`.  This can be changed
  by `["multi",doc=""]` (or whatever value you like) or by a blank line/comment
  at the top of the file.  `doc=fromNimble("description", nmblData)` is another
  partially automagic option.

Version: 0.9.30
---------------
  Have `dispatch2` in `cligen/oldAPI.nim` nest generation/calling inside `proc`
  that sets a local `ClCfg` from its parameter.  This is to quiet `verbosity:2`
  bogus warnings about GC safety as well as to be example code for how a modern
  invocations can silence such warnings.  Also have `dispatch2` be noisy about
  unsupported features.

  Add `dispatchCf` & `initFromCLcf`, wrapped by `dispatch` & `initFromCL`,
  respectively.  `cf` symbol variants allow passing a `cf` parameter, e.g.
  `cf=myCfg`.  Non-cf variants do not.  In both cases, assigments to the
  `cfClg` global propagate fine, but the non-`cf` versions will not trigger
  any (bogus) GcUnsafe warnings under verbosity:2.  For discussion see:
    https://github.com/c-blake/cligen/pull/106
  This is a breaking change *only* if you are already using the brand new (as
  of v0.9.28) `cf` *parameter* to `dispatch` (or `initFromCL`).

  Remove `mandatoryOverride` parameter to `dispatchGen`/`dispatch` introduced
  in cligen-0.9.11 before we had real version support/`parseOnly` mode.  Manual
  `dispatchGen` and `parseOnly` modes (as shown in e.g., `test/ParseOnly.nim`)
  allows totally general CLI author logic to inspect what a CLI user entered
  before actual dispatch to a wrapped proc if such sophisticated inspection is
  desired.  [ I doubt anyone ever used the already more-sophisticated-than-
  likely-useful `mandatoryOverride`. ]

  Make `dispatch`/`dispatchGen`/`initGen`/`initFromCL` interfaces insensitive to
  style style with respect to strings corresponding to Nim identifiers (`help`/
  `short` table keys, `positional`, `suppress`, `implicitDefault`).

Version: 0.9.29
---------------
  Add feature requested in both https://github.com/c-blake/cligen/issues/2 and
  https://github.com/c-blake/cligen/issues/30 .  See initFromCL documentation
  and test/InitOb.nim, test/InitTup.nim for how to use.

  Both issue https://github.com/c-blake/cligen/issues/28 and
  https://github.com/c-blake/cligen/issues/100 had a desire for CLI author
  controlled help-casing.  Now whatever string key is uses in `help = { }` is
  what shows up in help output.  So, e.g., `help = { "print-DNA": "yadda" }`
  should show up as `-p, --print-DNA= ..`.  If there is no `help` entry then
  `helpCase` is still used (though it would be weird for a CLI author to care
  about help table output long option spelling more than the parameter help).

Version: 0.9.28
---------------

  TL;DR: **IF** your compile breaks, just change `dispatch` -> `dispatch2`.
  If that fails, read on to update your code to the new API.

  Do ancient TODO item/close https://github.com/c-blake/cligen/issues/43.
  Remove 2 unneeded & lift 9 "proc signature independent-ish/CLI stylistic"
  of 28 `dispatchGen` (26 `dispatch`) parameters into an object of the new
  type `ClCfg`.  The idea here is to lift anything that very likely "program
  global" in a `dispatchMulti` setting to set in one place.  Per-proc edits
  remain possible via distinct `ClCfg` instances.  The detailed mapping is:

    Old dispatchGen param | New way to adjust settings
    --------------------- | --------------------------
    version/cligenVersion | ClCfg.version:string #MUST be "--version" now
                          |   arg version=("a","b") --> clCfg.version="b"
                          |   cligenVersion="b" --> clCfg.version="b"
    requireSeparator      | ClCfg.reqSep
    helpTabColumnGap      | ClCfg.hTabCols
    helpTabMinLast        | ClCfg.hTabRowSep
    helpTabRowSep         | ClCfg.hTabColGap
    helpTabColumns        | ClCfg.hTabMinLast
    mandatoryHelp         | ClCfg.hTabVal4req
    sepChars              | ClCfg.sepChars
    opChars               | ClCfg.opChars
    shortHelp             | Gone; Use short={"help", '?'} instead
    prelude               | Gone; Just use `usage` directly instead

  Client code not messing with anything in the left column and always passing
  `dispatch` params via keywords should need no changes.  `dispatch` params
  start changing at slot 7 (now `cf`) via mutations/removals.  Param order is
  otherwise the same except for `noAutoEcho` moving to after `echoResult` and
  `stopWords` moving to after `mandatoryOverride`.  This seems unlikely to
  matter.  Keyword calling seems pretty compelling at >=7 params & examples
  all use it.  `template dispatch` shows the new full argument list.

  So, this change is BREAKING-ISH in that it MAY require client code updates,
  but only in rare cases.  Most likely only `version`/`cligenVersion` users
  need to do anything at all, and that is to just lift one assignment out of
  a parameter list/change one variable name.  The only loss in flexibility is
  "--version" spelling becoming as fixed as "--help" (flexibility to spell it
  otherwise was always pretty iffy, IMO).

  Apologies if I'm wrong about impact rarity, but 16 is much cleaner than 26
  and the new way is far more practical for `dispatchMulti` adjustments.  More
  changes like this are unlikely.  Remaining `dispatch` params depend strongly
  on formal parameter lists which are likely to vary across wrapped procs in
  a `dispatchMulti` setting (except `usage`/`echoResult`,`noAutoEcho` which
  have sub-sub-command/compile-time reasons to not move into `cf`).  After a
  trial period to resolve issues, I'll stamp a 1.0 version with the hope to
  make no more backward incompatible changes unless there is a great reason.

  An exported global var `clCfg`, the default for the new `cf` parameter, can
  simplify common cases.  Examples showing how to adjust the above settings
  the new way are in:
    `test/Version.nim`
    `test/FullyAutoMulti.nim`
    `test/HelpTabCols.nim`

  **Also** add `versionFromNimble` for `clCfg.version=versionFromNimble(..)`.

Version: 0.9.27
---------------
  Mostly just a release that supports nim-0.19.6.

Version: 0.9.26
---------------

  Get `dispatchMulti` working without sub-scopes with C++ backend (nim cpp)
  on Nim versions 0.19.2 and 0.19.4. For details see:
    https://github.com/c-blake/cligen/issues/94

Version: 0.9.25
---------------

  Add convenient mslice.Splitr abstraction for CLI utilities delimiting inputs
  in a variety of ways.  Add demo program examples/cols.nim showing use.

  Fix `dupBlock` bug related to table modification during iteration exposed
  by https://github.com/nim-lang/Nim/pull/11160

Version: 0.9.24
---------------

  Remove need for using `argcvt.argDf` in any custom `argHelp` impls.
  A deprecated identity proc is provided for transition.

  Have cligen.nim export all symbols needed by generated procs so `dispatch`
  can now be invoked in a sub-scope within a proc.  See `test/SubScope.nim`.

  In general, be more careful with namespace stuff.  Silence false positive
  warnings, and fix a few bugs.

  Have better `helpCase`-using ambiguity error messages.

Version: 0.9.23
---------------

  Add CLI-style insensitivity to subcommand name matching.  E.g.,
  `./test/FullyAutoMulti nel-ly` works (or ./test/FullyAutoMulti d-e-m-o
  for that matter).  To show a dash in help text requires using `cmdName`.

  Add unambiguous prefix matching for subcommand names.  E.g.,
  `./test/MultMultMult a c y`.

  Multi-commands now exit with status 1 on parsing errors (ambiguous or
  unknown subcommand names).

Version: 0.9.22
---------------

  Add ability to accept any unambiguous prefix spelling of long option keys
  like cmd / option autocompletion in most shells but without TAB key press
  or any shell support required). https://github.com/c-blake/cligen/issues/99

  Minor clean-ups.

Version: 0.9.20
---------------

  Some clean-up of the --help-syntax output, including mentioning style-
  insensitivity.

  Improve character literal escape interpretation (single digit octal and
  various standard abbreviations like \n ,\e, etc.) and also better match
  the non-printable rendering of such char's in default values.

  Add ability via helpCase to convert snake_case to kebab-case help text for
  long option keys and default values.

  Add ability to accept any unique prefix spelling of enum values (like cmd /
  option autocompletion in most shells but without TAB key involvement or any
  shell support required). ( See https://github.com/c-blake/cligen/issues/97
  and https://github.com/c-blake/cligen/issues/99 )

  Add a fully worked out not useless example program `examples/dups.nim`.
  Distribute several support modules for it that may help authors of similar
  CLI utilities via cligen/[tmUt, fileUt, osUt, sysUt, strUt, mfile, mslice].

  Adapt to several deprecations/changes in Nim.  Seems to work on 0.19.2 and
  0.19.4 as well as a current devel branch.  Also fix some bugs here & there.

Version: 0.9.19
---------------

  Get `test/MultiMulti.nim` and even `test/MultMultMult.nim` mostly working.
  Now you can create dizzyingly deeply nested subcommands (but you will
  likely need to write your own `parsecfg` and `mergeParams` rather than just
  using `include cligen/mergeCfgEnv` if you want to use that in a config file
  as `stdlib.parsecfg` is only one level deep). [ As part of this work, add a
  new string-instead-of symbol first [] parameter entry for `dispatchMulti`
  like parameter lists to control name of the generated multi dispatcher, and
  named params after that string are sent to the `dispatchGen` used internally
  for that dispatcher.  Right now this is a little buggy, but someday it
  should allow controlling things like cmdName, version, usage, etc. ]

  The type column for seq[T] in help tables is now the English plural of T
  instead of array(T).  This is both more brief and more human readable.

  Add newline stripping & then re-wrapping to terminal width for the main doc
  comment (in both command help and in a multi-command help table off to the
  side of each command).

  Add ability to `include cligen/mergeCfgEnv` between `import cligen` and
  `dispatch` to get a typical `parsecfg` and then `getEnv` initial filling
  of passed parameters.  It seems better to make CLI authors request this
  smartness rather than have it be on by default (since evars/cfg files may
  be in place already if the CLI names are too generic).  That said, if
  popular demand for on-by-default ensues then I am open-minded and we can
  have an `include cligen/mergeNoCfgEnv` instead.  Let me know.

  Add mergeNames to dispatchGen.  This is mostly for internal re-factoring
  purposes, but someone might find it useful for something else.

  Relax the need for `cmdName` in `dispatchMulti(qual.symb, cmdName)`.
  The last component of the `DotExpr` is used for `cmdName` by default.

  Introduce `clParseOptErr` for `requireSeparator=true` mode to flag
  `parseopt`-level errors.

  `dispatchMulti`-generated help has better gradual reveal semantics/more
  typical behavior (`help cmd` is now like `cmd --help`) { There is much less
  standardization in multi-command world for us to mimick }.  suggestions now
  also work for invocations with a subcommand and options afterward.

  Suggest correct alternatives for possibly misspelled enum values.

Version: 0.9.18
---------------

  This release adds some major features. ArneTheDuck asked for (approximately)
  mergeParams, alaviss asked for qualified proc name support, and TimotheeCour
  requested non-quitting invocation & something like setByParse and the new
  aggregate parsing and pointed out other bugs/helped implement some things.

  Generated dispatchers now have the same return type (including void) and
  the same return value of wrapped procs.  Abnormal control flow from bad or
  magic command parameters is communicated to the caller of a generated
  dispatcher by raising the HelpOnly, VersionOnly, and ParseError exceptions.
  Manual invocation of dispatchers probably needs to be updated accordingly,
  unless chatty exception messages are ok for your CLI users.

  `cligen` now tries to echo results if they are not-convertible to `int`.
  This feature can be deactivated via the `noAutoEcho=true` parameter to
  `dispatch`/`dispatchMulti`. { Since a 1-byte exit codes/mod 256 can be
  catastrophic truncation for many returns, it is possible trying to `echo`
  being the first step would be more user friendly.  However, if people want
  to write procs with various exit codes in mind, it's also hard to think of
  a more natural setup than just exiting with that integer return.  So, the
  need for the CLI author to supply an `echoResult=true` override remains. }

  `cligen` now gets its command parameters by calling `mergeParams()` which
  CLI authors may redefine arbitrarily (see `test/FullyAutoMulti.nim` and/or
  `README.md`).  Config files, environment variables or even network requests
  can be used to populate the `seq[string]` dispatchers parse.  Right now
  `mergeParams()` just returns `commandLineParams()`.  It could become smarter
  in the future if people ask.

  `argPre` and `argPost` have been retired.  If you happened to be using them
  you should be able to recreate (easily?) any behavior with `mergeParams()`.

  `cligen` now tries to detect CL user typos/spelling mistakes by suggesting
  nearby elements in both long option keys and subcommand names where "nearby"
  is according to an edit distance designed for detecting typos.

  Commands written with `dispatchMulti` now reveal information more gradually,
  not dumping the full set of all helps unless users request it with the help
  subcommand which they are informed they can do upon any error.  Similarly,
  `dispatchGen` generates commands that only print full help upon `--help` or
  `-h` (or whatever `shortHelp` is), but tells the user how to ask for more.

  `dispatchGen` now takes a couple new args: `dispatchName` and `setByParse`,
  documented in the doc comment.  `dispatchName` lets you to override the
  default "dispatch" & $cmdName dispatcher naming (note this is different than
  the old `"dispatch" & $pro` default *if* you set `cmdName`, but you can now
  recover the old name with `dispatchName=` if needed).

  `setByParse` is a way to catch the entire sequence of `parseopt3` parsed
  strings, unparsed values, error messages and status conditions assigned to
  any parameter during the parse in command-line order.  This expert mode is
  currently only available in `dispatchGen`.  So, manual dispatch calling is
  required (eg. `dispatchGen(myProc, setByParse=addr(x)); dispatchMyProc()`).
  NOTE: This interface is a first attempt and may change in the future.

  Generated dispatchers now take a `parseOnly` flag which does everything
  except dispatch to the wrapped proc which may be useful in combination with
  the new `setByParse`.

  `dispatchGen` now generates a compile-time error if you use a parameter name
  not in the wrapped proc for `help`, `short`, `suppress`, `implicitDefault`,
  or `mandatoryOverride`.

  Unknown operators in the default `argParse` implementations for aggregates
  (`string`, `seq[T]`, etc.) now produce an error message.

  `positional`="" to dispatch/dispatchGen now disables entirely inference of
  what proc parameter catches positionals.

  `help["positionalName"]` will now be used in the one-line command summary as
  a help string for the parameter which catches positionals.  It defaults to
  a Nim-esque `[ <paramName>: <type> ]`.

  Command-line syntax for aggregate types like `seq[T]` has changed quite a
  bit to be both simpler and more general/capable.  There is a non-delimited
  "single assignment per command-param" mode where users go `--foo^=atFront`
  to pre-pend.  No delimiting rule is needed since the user must re-issue an
  option to give multi-arguments.  There is also a more expert mode that does
  "splitting-assignments" where operators like `^=` get a `,` prefix like
  `,^=` and CL users always specify delimiters as the first char of a value,
  `-f,=,a,b,c` like common /search/replace substitution syntaxes.  Split-mode
  lets CL users assign many elements in one command parameter or clobber a
  whole collection with `,@=`.  See argcvt documentation for more details.

  The `delimit` parameter to `dispatch` has been retired.

  There is a new --help-syntax line item for all commands which emits a
  hopefully eventually user-friendly description of particulars related to
  syntax for cligen commands, a syntax which has some unique extensions.

Version: 0.9.17
---------------

  Add ability for [1] element of Version 2-tuple-literals to be compile-time
  constant strings rather than string literals.  See `test/Version.nim`.
  [ This also works for `cligenVersion`, but you must `const foo = ..` and
  then `cligenVersion = foo` since `cligenVersion` itself is not and
  should not be a compile-time constant. ]

  Add ability for top-level command in `dispatchMulti` to accept "--version"
  to print some version string.  Just set `cligenVersion = "my version"`
  somewhere after `import cligen` but before `dispatchMulti`.

  Fix bug where cmdName was not being compared with `eqIdent`.

  Fix subtle new nil bug https://github.com/c-blake/cligen/issues/41

  More informative error message when non-option arguments are passed.

Version: 0.9.14
---------------

  Add range checking for all numeric types to argParseHelpNum

  Adapt code to new Nim nil world order.  One visible consequence is that
  passing empty values to string/cstring type parameters is allowed/easy.

Version: 0.9.13
---------------

  Add `version` parameter to `dispatchGen` and `dispatch`.

  Send "--help" and "--version"-type output to `stdout` not `stderr` for
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

  Add new `mandatoryOverride` parameter to dispatchGen/dispatch for
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

 2. `argParse` and `argHelp` are now `proc`s taking `var` parameters to
    assign, not templates and both take a new `argcvtParams` object to
    hopefully never have to change the signature of these symbols again.
    Anyone defining `argParse`/`argHelp` will have to update their code.

    These should probably always have been procs with var parameters.  Doing
    so now was motivated to implemenet generic support of collections (`set`
    and `seq`) of any `enum` type.

 3. `argHelp` is simplified.  It needs only to return a len 3 `seq` - the
    keys column (usually just `a.argKeys`), the type column and the default
    value column.  See `argcvt` for examples.

 4. `parseopt3` can now capture the separator text used by CLI users which
    includes any trailing characters in `opChars`.  `argParse` can access
    such text to implement things like `--mySeq+=foo,bar`.

 5. Boolean parameters no longer toggle back and forth forever by default. They
    now only flip from *their default to its opposite*.  There could be other
    types/situations for which knowing the default is useful and `argParse`
    in general has access to the triple (current, default, new as a string).
    For discussion see https://github.com/c-blake/cligen/issues/16 

 6. `enum` types are supported generically.

 7. `seq[T]` and `set[T]` are supported generically.  I.e., if there is an
    `argParse` and `argHelp` for a new type `T` then `seq` and `set`
    containing that type are automatically supported.  `argcvt` documentation
    describes delimiting syntax for aggregate/collection types.
