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

Cheat-sheat:

for `foo` of any type:
* `--foo=val` is same as `--foo:val` and `--foo val`
* likewise with -f instead of --foo; in addition -fval is also possible

* case of `bool`:
-f, --foo      bool           true           set foo
  these set to true: `-f` `-f:true` `-f=true` `-f true`
  multiple bool flags can combine: `-abc` means `-a -b -c`

* case of `string`:
-f=, --foo=    string         "bar"          set foo
  --foo=val  => `val`               : clobbers
  --foo=     => ``                  : clears
  --foo+=val => `barval`            : append
  --foo^=val => `valbar             : prepend

* case of `int`, `float`:
-f=, --foo=    float          10.2            set foo
  --foo=30.4  => `30.4`             : assign

* case of `array(string)`:
-f=, --foo=    array(string)  b1,b2    append 1 val to foo
single val syntaxes
--foo=val    => `b1,b2,val`         : append
--foo=       => `b1,b2,""`          : append (an empty string)
--foo+=val   => `b1,b2,val`         : append
--foo^=val   => `val,b1,b2`         : prepend
--foo-=b1  => `b2`                  : remove (0 or more) entries equal to `b1`

multi-val syntaxes
--foo,=        => ``                : clears
--foo,=,v1,v2  => `b1,b2,v1,v2`     : append multi
--foo,=/v1/    => `b1,b2,v1,""      : ditto (note trailing delimiter effect)
--foo,=,       => `b1,b2,""`        : ditto
--foo,+=,v1,v2 => `b1,b2,v1,v2`     : append multi
--foo,^=,v1,v2 => `v1,v2,b1,b2`     : prepend multi
--foo,-=,b1,b2 => ``                : removes multi (here, ends up empty)
--foo,@=,v1,v2 => `v1,v2`           : clobbering multi assignment
"""
