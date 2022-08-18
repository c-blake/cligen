RELEASE NOTES
=============

Version: 1.5.28
---------------

  - Make `cligen/macUt.summaryOfModule` operate how proc doc comments always
    have (text indented relative to first row is treated as pre-formatted).
    In the unlikely event this is unwanted, you can always pass whatever `doc`
    to `dispatchMulti(["multi",...])`.  Show in `test/MultiMulti.nim`.

  - Fix old range clipping & code-prefixing bugs in 256-color xterm support.

Version: 1.5.27
---------------

  - Fix a possible deadlock with NUL|newline-terminated `procpool` protocols.

  - Add a few more conveniences to ease porting code from string to `MSlice`
    (slicing an `MSlice` with `HSlice` constructors, `endsWith`, `find`).

  - Add `sysUt/newSeqNoInit[T: Ordinal|SomeFloat]` like `newSeqUninitialized[T]`
    but less constrained on T.

Version: 1.5.26
---------------

  - This is a small, almost trivial release mostly just to bump the version
    number so that @ringabout (formerly xflywind)'s `shallowCopy` removal
    patch has a tagged version.

Version: 1.5.25
---------------

  - Add `--define:cgCfgNone` to compile-time disable config file processing.
    This both saves about 50|100K on space-optimized (danger|not) binaries and
    gives CLauthors unquestioned authority on various settings & behaviors.
    Some other size optimization work was done as part of this.  See also
    discussion/analysis in https://github.com/c-blake/cligen/issues/207
    cligen space overhead with the new size trimmings is now as small (or as
    big) as build mode variation for an empty file.

  - BREAKING CHANGE: in the both unlikely *and* unwise case that you relied
    upon `import cligen/humanUt` exporting `initHashSet`, `toHashSet` - you
    can no longer.

  - Harden `cligen/procpool` a bit more and add a new `examples/piPar.nim` that
    runs 1000s of times faster than the perf-buggy tests/parallel/tpi.nim in
    Nim or the examples/e02_parallel_pi.nim in the status taskpools repo.

  - Add `docCommentAdd` (courtesy of @Vindaar private communication who also
    added the utility API `nextSlice`).
    
  - Add a couple calls to make mfile behave more like a string, but less
    automatically in that an external integer "used length" variable is needed.

  - Add simpler way to use `cligen/tab` (Newspaper columns often what you want).

  - Add `sysUt.echoQuit130` proc for `setControlCHook` to ease "making Unix-y".

  - Various documentation updates/fixes/unused import clean-ups.

Version: 1.5.24
---------------
  - Fix long-standing bug in `--long-=foo` for `long: seq[T]` params.

  - Change mfile/MFile.(mem|len) to be an `MSlice` w/back compat. accessors.

  - Fix a long-standing bug in const/static value passing
    (https://github.com/c-blake/cligen/issues/209)

  - Add `err=stderr` override in `cligen/mfile` & add ability to capture
    `MFile` object from `mSlices` iterator and a couple `cligen/mslice` procs
    to make it easier to use an `MSlice` like a `string`.

  - Fix some OSX & old Nim portability issues only manifesting in client code.

  - Fix chance deadlock possibility in cligen/procpool and add:
    - `select` timeouts to `initProcPool`
    - `examples/ppBench.nim` to measure amortized dispatch overhead
    - `examples/fkindc.nim` "overview" variant of `only` using differing
       request-reply framing

  - For convenience, add `raiseCtrlC` to `initProcPool`, defaulting to silence
    (by default) dozens of duplicate stack traces upon user-interrupt.

  - `examples/dups.nim` no longer needs the OpenMP `||` iterator (although
    parallelism was always mostly unhelpful there anyway).

  - BREAKING CHANGE: Alter interface for procpool work() procs to receive the
    (r)ead aka request fd and (w)rite aka reply fd.  The former approach to
    assume fd 0, fd 1 was too error prone (while having the nice-ish property of
    making kids conceptually stdin-stdout filters).  Also, be careful with stdio
    buffers across forks and add simpler to use `open(cint)` to `cligen/osUt` to
    make this setup only slightly less usable than before, but with users giving
    buffering modes/sizes which can matter.  See commit logs for examples/[only,
    fkindc, dups, grl, gl, ppBench] for guidance to adjust your usage.

Version: 1.5.23
---------------
  - Slightly more terse default `enum` help messages

  - Made default `argParse`/`argHelp` work for `Slice[float]`

Version: 1.5.22
---------------
  - Fix 3 year old annoyance having `mergeParams` not default to `@[cmdName]`.
    It is now often no longer necessary to do that to pull from env.vars/cfgs
    if the desired names match the default conventions (and if they don't then
    you probably want `mergeNames` or your own `mergeParams`).

  - Add text template string interpolation/macro expander-processor framework
    as strUt.tmplParse with `examples/tmpl.nim` showing a simple usage.

  - Overhaul / generalize `strUt.fmtUncertain` system to use new `tmplParse`
    to allow format-string-based whatever you like feature and (accordingly)
    drop the `pm` parameter to some old API calls that are much simpler and
    otherwise do not need to go away.

  - `rp` is easier on newbie users & can leverage incremental compilation (when
    IC does not SEGV compiler) for ~150..350 ms start-up times w/tcc..gcc -O0.
    Put `cache = "+--incremental:on"` into `~/.config/rp` to use by default.
    `gcc -O3` is under 1 second, but very first compile is 2-3X longer than
    with no IC, though (i.e. notable 1st-time uncached v. cached trade-off.)
    The derived https://github.com/benhoyt/prig & article may be of interest.

Version: 1.5.21
---------------
  - Re-factor `fmtUncertain` & friends to be less format & re-parse stupid and
    add fmtUncertainVal for just the value, but rounded as per error.

  - add "required" to [layout] section of ~/.config/cligen[/config]; Use val4req
    consistently in its three places - error message, initial command summary,
    and the help table.  This is useful since consistency eases learning, and
    also nice for more rapid end-user understanding of unexpected program
    failures (maybe when barely awake/etc.)  E.g., some can put ANSI SGR color
    escapes in their config files to bold/red/blink/whatever while others can
    not as per personal preference.  Meanwhile others can shrink "REQUIRED" to
    the half-as-long "NEED" which could narrow help tables avoiding word wraps
    and terminal size is also personal.

  - Build clean with `--styleCheck:hint --styleCheck:usages` (after @xflywind's
    stdlib work).

Version: 1.5.20
---------------

  Began a scope discussion: https://github.com/c-blake/cligen/discussions/201

  Add a new exception type for the main CLI generation framework that allows
  raising user syntax/semantic errors when the CLauthor controls (or explicitly
  wraps) an API.  Either a terse message or the full help string interpolated in
  is possible (via ${HELP}).  See `test/UserError.nim` for how to use.  This
  feature vaguely relates to these issues:
    https://github.com/c-blake/cligen/issues/160
    https://github.com/c-blake/cligen/issues/180
    https://github.com/c-blake/cligen/issues/135

  Add `madvise` API to `posixUt`.

  Add `strip(MSlice)`, `firstN(MSlice)` to `mslice`;  Make w\* abbreviate
  "white" in mslice.initSep; Have `cligen/mslice.parseFloat`/ints take sum type
  including `openArray[char]` for more flexible deployment.

  Make cligen/strUt.(ecvt|fcvt) thread safety analyzer-safe with a compile-time
  proc to init `zeros` instead of using `strutils.repeat`.

  Add a convenience first param broadcaster macro `macUt.callsOn`.

  Rename `rp --test` to `where` and fix a few bugs (`pclose` on Windows, `isNan`
  for Nim<1.6, `textAttrRegisterAliases`, `tcc`-compat `osUt`).

Version: 1.5.19
---------------
  Add fast `ecvt`, `fcvt`, and pretty `fmtUncertain`.

Version: 1.5.18
---------------
  Speed-up compilation time for some use cases like `rp`.

Version: 1.5.17
---------------
  `parseInt` didn't do negatives; `parseFloat` was quite hosed. All better now
  and with a test suite.

Version: 1.5.16
---------------
  Avoid regular expr abbreviation connotations of `rx` by renaming to `rp`.

Version: 1.5.15
---------------
  Sorry for the slight 10 vs 10'u64 hiccup.

Version: 1.5.14
---------------
      
  Add `fmtUncertainMerged` - The Particle Data Group's neatly terse uncertainty
  notation { 12.34(56) = 12.34 +- 0.56 - 2 significant figures in the error and
  aligned digits.}. This scales to high & low exponents quite well. { One might
  argue a '/' could be clearer & shorter, as in 12.34/56, but this is non-std. }

  Add fast `MSlice` number parsers for `int` & `float`.  These do NOT need to
  first convert to a Nim `string`.

  Add `rx` - a row executor/row processer program generator that allows a work
  flow like "awk one-liners" but for Nim programs..So, a delay to compile, but
  then static typing & much better (fully compiled/optimized) performance on
  meso-scale data like a few 100 million records.

Version: 1.5.13
---------------
  Add a connected components module `conncomp`; tweak a strUt/joins

Version: 1.5.12
---------------
  Add cligen/print module to satisfy forum requests.  While a bit out of place
  this addition got multiple hearts.

Version: 1.5.11
---------------
  Add some utility code to `cligen/strUt` to suppress meaningless digits "the
  smart way" (or at least the way particle physicists have been doing it for >30
  years). { `fmtUncertain` scales fabulously to "precise" values, but is about
  as clunky as +- for values very uncertain relative to their mean. }

Version: 1.5.10
---------------
  Both start & stop ANSI SGR sequences can be included in all the emitted help.
  This can make it easier to automate translation to troff for man page
  contexts. Also add a few new `osUt` utility APIs (`file(Older|Newer)Than`,
  `touch`, `walkPatSorted`, `clearDir`, `autoOpen`, `autoClose`, `isatty(fd)`}

Version: 1.5.9
--------------
    Fix bug in `cligen/argcvt` parsing enums where one could not prefix another
    (e.g. `blue` & `bluegreen` could not be in the same enum set).

Version: 1.5.8
--------------
  As Nim-1.6 approaches, tweak code to no longer generate warnings for the
  library itself or for example programs. Might be one or two not very hot code
  paths lingering.

Version: 1.5.7
--------------
  Better support CLuser-written config files via both `cligen`-included
  `cligen/clCfg(Init|Toml)` and CLauthor included `cligen/mergeCfgEnv` checking
  decls before import to block compiler issued duplicate import warnings.

  Also, update `cligen/clCfg(Init|Toml)` to find a simple `~/.config/cligen`
  file as opposed to only finding `~/.config/cligen/` directories. (Might be
  helpfully simpler for conscientious objectors to `LC_THEME` complexity.)

Version: 1.5.6
--------------
  Get most warnings suppressed in preparation for hopefully soon Nim-1.6.0.
  (`TaintedString` deprecations will probably warn until removed and then just
  go away since I try to support back to Nim-0.19.2).

  Also add some very easy to use time queries in `cligen/posixUt` and warn if
  `int` is not 64-bits.

Version: 1.5.5
--------------
  Mostly `procpool.noop` to ease life when there is no result to write back and
  then inside `osUt` we grew `popenr`, `popenw` & `pclose` and also `mkdirTo` &
  `mkdirOpen`, and `replacingUrite` (for `nio/lp2term`) and finally an ARM64
  portability thing for `cligen/magic`. (A few doc clean-ups, too.) 

Version: 1.5.4
--------------
  Fix a bug in mfile.mSlices; Add splitPathName for the *longest* extension
  unlike stdlib shortest extension, `mkdirOpen` and spruce up `procpool`
  including a new 8-bit clean message mode (via length-prefixed messages).
  Add a little demo program `grl` that competes well with `ripgrep` in
  some cases being noticably faster.

Version: 1.5.3
--------------
  The big one here is a new sigpipe configuration capability.  This only
  impacts newer versions of Nim.  A simple layout is:
    Older Nim:
      always traceback w/good debugging & SIGPIPE: Pipe closed regardless
    Newer Nim/devel and 1.6 & later:
      isok  - exit 0 even with set -o pipefail
      raise - traceback only
      pass  - signal only; typically termination w/exit 128+signo=141
  The command-default can be set via clCfg.sigpipe while CL-end users can
  set (~/.config/cligen|~/.config/cligen/config):sigpipe = the same values
  (unless CLauthors override config file parsing to block it).

  This may seem complex, but only end CLusers can really know what signal
  protocol is least disruptive..whether they do `set -o pipefail` in shell
  configs, whether programs that their cligen programs in turn execve/etc.
  expect/need a default SIGPIPE disposition (not all such programs are Nim or
  even open source), whether a stack trace means anything to them, and even
  whether they compile their program to get much of a stack trace capability.

  Add `osUt.outu|erru` convenience shortcuts, tweak test.sh, and also adapt to
  newer nim-devel in other ways.

Version: 1.5.2
--------------
  Cleaner fix for Nim CI via `discarder` to discard if needed/possible and
  otherwise do nothing.  Simplifies both `cligenQuit` and `cligenHelp` and
  seems to work back to Nim-0.19.2.

  Properly raise on write errors in `osUt.urite`.

  Add `sysUt.seekable` to test seekability/random access of a Nim `File`.

Version: 1.5.1
--------------
  Probably no one but me uses procpool.eval, but its signature has been
  substantially simplified and a default output framer is also now provided
  for `initProcPool`.

  Quick release to address Nim important packages CI as per
  https://github.com/c-blake/cligen/pull/193#issuecomment-823941827

Version: 1.5.0
--------------

  Add range type ability (thanks to @SirNickolas). `test/RangeTypes.nim` has
  test/example code.

  Add ability to customize description column for help, help-syntax, version or
  to surgically suppress any such rows with `hTabSuppress`/`"CLIGEN-NOHELP"`.

  Add `$CLIGEN_WIDTH` (really whatever `clCfg.widthEnv` says) to allow user
  override of detected terminal width.  (No controlling terminal processes
  could already use `COLUMNS`).  Set to `"AUTO"` to have a value, but still
  fall back to OS terminal interface calls.

  Try to get ahead of eventual removal of `TaintedString`.

  Fix a few gotchas/inadequacies in `mfile` & `mlice` for mmap prot/flags/using
  the buffers.  Rename `mslice.Splitr` -> `mslice.Sep`.  Leave deprecated
  aliases.  Add more general split-like API called `frame`.  This is nice when
  you want to write a text filter that transforms "inner text" but leaves the
  outer text alone.

  Generalize `textUt.alignTable` to allow caller to specify left/right/center.

  Add a little `osUt.setAffinity` api to ease "createThread & setAffinity" use.

Version: 1.4.1
--------------
  Work around a long-standing nim-devel (but not 1.4) cpp codegen bug.

  Add some utility code and a test program to ease bulk parallelization in the
  common case that a giant file has enough statistical line-length regularity
  that subdividing by bytes are a good guess to subdividing by lines (or some
  other variable record delimiting).  This can make such parallelization just
  a few lines of code allowing users to focus on their application logic.
  See https://forum.nim-lang.org/t/7447 for one such user in need.

Version: 1.4.0
--------------
  Lift NUL-terminated easily boundable framing out of cligen/procpool into
  `examples/only.nim`.  In the unlikely event you were using this, you will
  need to implement framing yourself (which pairs well with implementing the
  worker generating output to frame in the first place).

  Robustify against existence of stdlib-provided `toCritBits`.
  Minimize ANSI SGR escape off string to "\e[m".
  Enhance sysUt.toItr to work with iterators yielding more general values.
  Robustify `mfile` to not emit errors on empty files.

Version: 1.3.2
--------------
  Remove prefetching optimization idea, anyway.  On AMD 2950X, it was quite a
  bit slower anyway.

  Better fix to deactivate prefetch doing anything unless user activates (and
  maybe uses special gcc flags, too.).  `cligen/prefix` module is retained for
  backward compatibility { no longer touching compiler flags at all }.

Version: 1.3.1
--------------
  Quick fix to deactivate mslice prefetch causing build problems for some.
  { Should at least be guarded by defined(prefetch) or something. }

Version: 1.3.0
--------------
  More compatibility fixes; Deprecation warning removals; Use std/ qualifiers
  on many/most imports; Use `type` not `typeof` to still work on Nim-0.19.2.

  Better github CI integration (thanks to @jiro4989)

  Allow wrapped proc to have a `version` parameter already.

  More efficient environment variable defaulting approach for `CLIGEN_CONFIG`.

  Some library improvements..Make `mfile.mopen` more robust for FIFO/named pipe
  `path` parameters; Generalize `textUt.stripSGR` to `textUt.stripEsc` to strip
  both SGR and OSC terminal escape sequences (thanks to @SolitudeSF);
  `dents.forPath` follows symlinks when filling in `lst` only `if follow`;
  Improve `sysUt.toItr` based on excellent @slonik-az idea in the Forum;
  Speed-up `posixUt.readFile` by just doing one big enough allocation+read.

Version: 1.2.2
--------------
  Just compatibility fixes.

Version: 1.2.1
--------------
  Empty helpSyntax string suppresses showing --help-syntax in the automated
  help table.

  Compatibility fix for pending Nim changes.

Version: 1.2.0
--------------

  Roll our own very partial rST/markdown-like font markup parser to remove
  run-time dependency on PCRE libraries for easier deployment.

  Add `cgCfg.helpSyntax` field which CLI authors can default differently and
  `[templates]/helpSyntax` which end CL users can override to say whatever.

  The type `ClCfg`, the global compile-time default `clCfg`, and the two
  provided config file parsers have grown ways to suppress prefix matching.
  A CLauthor can set clCfg.longPfxOk = false and then his (savvy) CLusers
  can override that default with longPrefixOk = false in the syntax section
  of their config file (unless the CLauthor doesn't use a config file or
  overrides the provided impls...).

  Add `sysUt.toItr` to simplify life when using closure iterators.  Show use
  in `trie.leaves` as a "recursive iterator" (as close as makes sense in Nim).

  Add minimal proof-of-concept Python multiprocessing-like `procpool` module &
  `examples/only` and `examples/dirq` using inotify as a reliable OS queue.

Version: 1.1.0
---------------
  Add fast file tree walk iteration `cligen/dents.forPath`.  On Linux (esp.
  true Intel), sys\_batch & -d:batch afford even more speed-ups.  Add `chom.nim`
  example to also exhibit some fancy "octal integer" argparse usage.  Add `rr`,
  `dirt`, and `du` examples to show non-trivial cases needing a recursion-aware
  recursion abstraction.

  Replace `NimVersion vs ""` tests with `(NimMajor,NimMinor,NimPatch)` tests.

  Add some support inequality routines for `cligen/statx.StatxTs`.

  Repo does auto-CI runs & auto-doc gen now thanks to @jiro4989 and @kaushalmodi
  { Testing pre-commit is better (both less waiting and, well, pre-commit). }

  Added `$doc` and `$help[param]` rendering via any non-nil `clCfg.render`
  string-to-string transformer.  One easy way to get one is to add a `[render]`
  section to your `~/.config/cligen/config` file that sets at least one of
  singleStar, doubleStar, tripleStar, singleBQuo, doubleBQuo to some "on ; off"
  pair.  That will do an initRstMdSGR/render on $doc and $help[param] text.

  As follow-on from the above better help formating work, also do a smarter
  word wrap that A) minimizes the Lp norm of the extra-space-at-EOL vector,
  B) is better about preserving the blank line structure in inputs, and C) can
  still wrap lines in paragraphs that are outside of indented lines (instead
  of the prior any-indent-anywhere ==> whole string pre-formatted).

  The top-level help of a `dispatchMulti` command is now rendered and wrapped
  just like the `$doc` for each subcommand.

  Add more conveniences in cligen/mslice, cilgen/osUt, & factor out stripSGR.

Version: 1.0.0
---------------
  No new problems in the past few weeks => call it time to stamp 1.0.  (Truly
  well argued/motivated breaking changes will always remain possible, but do
  not seem super likely.)

Version: 0.9.47
---------------
  Try to clean up documentation of new config file/colorization features.

  Fix minor bugs in `cligen/abbrev.expandFit` & `examples/dups.nim` on Android.

  Address long-standing (since the beginning) bug when a parameter name is one
  letter and collides with either automatically selected or manually specified
  short options.  https://github.com/c-blake/cligen/issues/146

  Address long-standing surprising behavior where `mergeParams` is called twice
  for `dispatch` style.  Still called N+2 times for `dispatchMulti` until some
  re-write of that to not itself use dispatchGen on some generated proc.  Update
  0-level `cligen/mergeCfgEnv.nim`; add 1-level `cligen/mergeCfgEnvMulti.nim`
  example/library impls.  The only impact of this is that people (maybe no one)
  calling `dispatchCf` directly (to use its `cf` parameter to pass a CLauthor
  `ClCfg`) must now provide a command line themselves via `dispatchCf`'s new
  `cmdLine` parameter.  They can call `mergeParams` there to recreate the old
  broken behavior exactly or do something else which is probably more useful.

Version: 0.9.46
---------------
  Silence `argcvt.nim` implicit copy warnings in `--gc:arc` mode.  Problem cases
  (no move warns but using move fails) remain at: cligen.nim:{490,504}, and
  cfUt.nim:16 and cligen/clCfgInit.nim:14 (at least..maybe others).  The exact
  cases will be specific to your exact version of Nim as `gc:arc` is in a rapid
  development phase.

  Added convenience wrappers `recEntries`, `paths` in `cligen/posixUt.nim` for
  fully general path inputs often nice in CL utils.  See `examples/dups.nim`.

  Remove `cligen/oldAPI.nim` and its `include` in `cligen.nim`.  I'm not sure
  anyone ever used this, but it is especially defunct given `clCfgInit`.

  Add `test/FancyRepeats2.nim` to show a second way to do it.

  Add one "output breaking" change to simplify implementation of dropping (in
  `dispatchMulti` context) the "Usage:\n" header more like how skipping repeats
  of -h,--help and --help-syntax works.  If you were passing your own `usage`
  template anywhere then you will probably want to delete the "Usage:" prefix.
  It will work ok with it still there, but be repetitive/ugly.

  --

  The above is part of a large feature addition to allow opt-in presentation
  (and some CL syntax) configuration by CL end users -- probably How It Always
  Should Have Been (TM) since CL authors can only anticipate so much.  This
  configuration is via the include `cligen/cfCfgInit.nim` by default which reads
  `~/.config/cligen/config`|`~/.config/cligen files`.  `configs/config` in the
  distribution is an example config and the Wiki will have more details someday.

  If you hate parsecfg and don't mind an additional parsetoml dependency,
  @kaushalmodi has contributed an alternate config parser with an example in
  `configs/config.toml`.  Just compile with `-d:cgCfgToml` to activate and
  see `configs/config.toml`.

  If you really hate providing CL end users with some/all of this flexibility
  then you can always write your own project-specific `cligen/clCfgInit.nim`.
  For maximum terminal compatibility `cligen` does no colors by default.  If
  your user base is un-picky, such as "only yourself", you can also provide
  colorful defaults via compile time `clCfg` hacking.

  Further, if the user sets the `$NO_COLOR` environment variable to any value
  then all escape sequences are suppressed.  This can be helpful for programs
  that parse the output of `cmd --help`.  E.g., for the Zsh auto-complete system
  you want to patch the `_call_program` function to export `NO_COLOR=1`.  I am
  considering interpreting the double negative `NO_COLOR=notty` as a tty-test.
  { Often one wants colors piped to `less -r`.  So, that alone isn't enough. }

  Environment-variable sensitive `[include__VAR]` can be used to set up night
  mode/day mode https://github.com/c-blake/cligen/wiki/Color-themes-schemes

  Since this new feature addition is a large change with slight compatibility
  ramifications, and more importantly since it seems likely to inspire follow-on
  requests that may be hard to make compatibly, I am deferring the 1.0.0 stamp
  until a release or two from now.

Version: 0.9.45
---------------
  Make compatible with pre-1.0 Nim.

  This is the last pre-1.0 release with 1.0 likely at the end of April.  Please
  make any feature requests you think may require breaking changes now or be
  prepared for even more than usual pushback in the interests of stability.
  (Truly well argued/motivated breaking changes will always remain possible.)

Version: 0.9.44
---------------
  Fix bad bug in `posixUt.recEntries` where it only worked for "." and make
  the warning message more clear/specific about re-visitation not looping.

  Have `argcvt.ElementError` inherit from `ValueError` not `Exception`.

  Make `helpDump` in `dispatchMulti` skip repetitive --help/--help-syntax rows
  with instead just a note at the top about general availability.

  I've added some `move` annotations to silence many gc:arc warnings, but many
  (cligen.nim:457, cligen.nim:471, cfUt.nim:16, argcvt.nim:308, argcvt.nim:318,
  argcvt.nim:320) fail with `move` due to immutability/etc. (the very first only
  at runtime) while warning without move.  If you find any you can silence with
  a `move` successfully let me know.

Version: 0.9.43
---------------
  In most contexts for most parameters you can now use a compile-time `const`
  value instead of a literal.

  Default `cligen/helpTmpl.nim:clUse` dropped overly chatty text redundant
  upon first real line of `--help-syntax`.

  Updated generated documentation and include CSS (Thanks, @kaushalmodi!)

  `cligen/textUt.match` changed its return type to `tuple[key:string, val:T]`.
  If anyone else is using this, existing call sites need only add a `.val` to
  track the change.  (Sometimes it is nice/necessary to know the matched key.)
  Also for `Table` similarity, added `cligen/textUt.toCritBitTree`.  For UI
  ease add `match` overload to prints to a File if non-`nil` and also raise.

  `cligen/posixUt` grew an infinite-symlink-loop avoidant `recEntries` with a
  more traditional Unix API (user just says `follow=true` or not the way many
  Unix CLI utilities work) than `os.walkDirRec`.  At the API level, pointers
  are also optionally accepted to let callers receive all the metadata acquired
  and so avoid duplicate syscalls.

Version: 0.9.42
---------------
  Allow stropped aka \`backquoted\` params to have a `help` entry.  Add new
  test program for such.  Probably the first of only quite a few places we will
  need `maybeDestrop`.

  Add `cligen.initDispatchGen`.  See doc comment/commit comment for details.

  `textUt.getAll(cb: CritBitTree[T], key: string)` now returns a seq of len==1
  when the key is in the table (even if that key prefixes other keys).

  Add `cligen/osUt.loadSym` proc combining loadLib and symAddr operations.

  Add `cligen/abbrev.expandFit` to re-expand glob patterns as much as can be
  done without impacting a terminal column structure.  (Used by `lc`.)  Also
  add pattern quoting option (5th column to `Abbrev` initializer is "?;[]..")
  that can happen independently of `expandFit` as well as after it.

  `cligen/abbrev.uniqueAbbrevs` signature changes slightly.

Version: 0.9.41
---------------
  Fixed some bugs for `setByParse` users.

  Change the default `hTabSuppress` to `"CLIGEN-NOHELP"` to be more specific
  about what it does and kind of namespace it to be cligen-specific, too.

Version: 0.9.40
---------------
  `help["param"] == "SUPPRESS"` now removes param from the generated help
  table.  In the unlikely event you had that (case sensitive) string as a
  parameter help string, the string "SUPPRESS" can be adjusted via
  `clCfg.hTabSuppress`.

  Work around `csize` definition thrashing in Nim-actual by defining our own
  non-exported `csize` in modules that need it to the uint version.  Code seems
  to test out ok in all Nim versions >= 0.19.2.  About the only downside is
  that a private & different `csize` could cause some confusion to casual
  on-lookers/readers rapidly switching between in-cligen/out-of-cligen modules.
  Anyway, you probably do not want to use cligen v0.9.39 for anything, but
  nimble lets you say <=0.9.38 or >=0.9.40 (or #head, etc.).

Version: 0.9.39
---------------
  initFromCL` now works on ref|ptr object types.  See `test/InitObRef.nim` and
  `test/InitObPtr.nim` and https://github.com/c-blake/cligen/issues/118
  discussion.

  Fixed up several places that needed adjustment due to csize -> uint.

Version: 0.9.38
---------------
  Fix a little bug blocking abbrev(mx>0).

  Move `cmp`, `<=`, `-`(a, b: Timespec) from `statx` to `posixUt`.
  Add argParse/argHelp support for Timespec.

  cligen/[statx, magic] made somewhat autoconfiguring. (magic could probably
  use more paths.  PRs welcome.)

  ClAlias tuples have grown a 4th slot for default CL-author provided alias
  definitions and a provided default reference.  CL-author must pass a
  seq[seq[string]] empty list even if these new features are not used (to
  match the ClAlias type).  See test/UserAliases.nim

  Some new convenience API calls: `macUt.docFromProc`, textUt.termAlign\*,
  mfile.inCore posixUt.readFile st_inode nice nanosleep.

  `prsOnlyId` fix for newer Nim quote do: behavior

  .config/prog/config dir looked for before .config/prog file

  cfToCL includes are cfg-file relative paths if they don't start with /

  includes apply to the current subcommand section (config files for multi-cmds)

  only first paragraph of subcmd descrips are used in summary table

  readlink 1st arg renamed to path

  mergeParams no longer fails w/empty seq cmdNames arg and mergeParams is more
  consistenly always used instead of commandLineParams

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
