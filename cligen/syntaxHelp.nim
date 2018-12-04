const syntaxHelp = """
This should maybe be re-written to be oriented toward a CLI user, not a
CLI author. { and re-written and written again until questions stop. }
In particular, it's hard to know how much Nim knowledge or beyond shell
programming knowledge in general to assume on the part of a CLI user.

AGGREGATES (seq, set, HashSet, string, ..)

cligen can parse for seq[T] and similar aggregates (set[T], HashSet[T]) with
a full complement of operations: prepend (^=), subtract/delete (-=), as well
as the usual append (+= or just = or nothing at all - as is customary for
compiler commands, e.g. cc -Ipath1 -Ipath2).

string is treated more as a scalar variable by cligen in that an unqualified
[:=<SPACE>] overwrites/clobbers rather than appending, but += does append if
desired.  E.g., --foo="" overwrites the value to be an empty string,
--foo+="" leaves it unaltered, and --foo^=new prepends "new".

cligen also supports a ,-prefixed family of enhanced Delimiter-Prefixed
Separated Value operators that allow passing multiple slots to the above
operators.  DPSV is like typical regex substitution syntax, e.g., /old/new or
%search%replace where the first char indicates the delimiter for the rest.
Delimiting is strict. (E.g., --foo,^=/old/new/ prepends 3 items @["old",
"new", ""] to some foo: seq[string]).  Available only in the ,-family is also
,@ as in ,@=<D>V1<D>V2...  which does a clobbering assignment of @["V1",
"V2", ...].  No delimiter at all (i.e. "--foo,@=") clips any aggregate to its
empty version, e.g. @[].
"""
