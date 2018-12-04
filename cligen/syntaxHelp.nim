#[
This should maybe be re-written to be oriented toward a CLI user, not a
CLI author. { and re-written and written again until questions stop. }
In particular, it's hard to know how much Nim knowledge or beyond shell
programming knowledge in general to assume on the part of a CLI user.
]#

const syntaxHelp = """
AGGREGATES (seq, set, HashSet, string, ..)

cligen can parse `seq[T]` and similar aggregates (`set[T]`, `HashSet[T]`) with
a full complement of operations: prepend (`^=`), subtract/delete (`-=`), as well
as the usual append (`+=` or just `=` or nothing at all, as is customary for
compiler commands, e.g. `-Ipath1` in `cc -Ipath1 -Ipath2`).

`string` is treated more as a scalar variable by cligen in that an unqualified
[:=<SPACE>] overwrites/clobbers rather than appending, but `+=` does append if
desired.  E.g., `--foo=""` overwrites the value to be an empty string,
`--foo+=""` leaves it unaltered, and `--foo^=bar` prepends `bar`.

cligen also supports a `,`-prefixed family of enhanced Delimiter-Prefixed
Separated Value (DPSV) operators that allow passing multiple slots to the above
operators.  DPSV is like typical regex substitution syntax, e.g., `/old/new` or
`%search%replace` where the first char indicates the delimiter for the rest.
Delimiting is strict. (E.g., `--foo,^=/foo/` prepends 2 items `["foo", ""]` to
some aggregate `foo`).  Available only in the `,`-family is also
`,@=` as in `,@=<D>V1<D>V2`  which does a clobbering assignment of
`["V1", "V2"]`.  No delimiter at all (i.e. `--foo,=`) clips any aggregate to its
empty version, e.g. `[]`.
"""
