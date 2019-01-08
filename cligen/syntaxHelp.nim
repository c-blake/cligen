#[
This should maybe be re-written to be oriented toward a CLI user, not a
CLI author. { and re-written and written again until questions stop. }
In particular, it's hard to know how much Nim knowledge or beyond shell
programming knowledge in general to assume on the part of a CLI user.
]#

const syntaxHelp = """
cligen-using commands can parse plural types like "strings" with several
updating operations: prepend ("^="), subtract/delete ("-="), as well as the
usual append ("+=", just "=", or nothing at all, as is customary for compiler
commands, eg. "cc -Ipath1 -Ipath2").  "string" is treated more as singular
variable by cligen in that unqualified assignment overwrites/clobbers, but "+="
appends if desired.

Plural types also support a ','-prefixed family of Delimiter-Prefixed Separated
Value (DPSV) operators that allow passing multiple slots to the above operators
in one command parameter.  DPSV is like typical regex substitution syntax (eg.,
"/old/new" or "%search%replace") where the first character of a value indicates
the delimiter for the rest.  Delimiting is strict (a trailing delimiter means an
empty slot).  No delimiter ("--foo,=") sets any aggregate to its empty version.
",@=" works like a set empty followed by an append.  I.e., "--foo,@=/V1/V2" is
just like "--foo,= --foo=/V1/V2".

Cheat sheet:
  * "--foo=val" is same as "--foo:val" and "--foo val"
  * likewise with -f instead of --foo; in addition -fval is also possible

  * "bool" values for flags "foo", "bar" with short options 'f', 'b':
    default value false: -f | --foo sets the flag to true
    default value true: -b | --bar sets the flag to false
    "-f=true" or "-b=true" always sets either to true (likewise for "false").
    Multiple bool flags can combine: "-bf" means "-b -f"
    "on",  "yes", "t", "y", and "1" are all synonyms for "true"
    "off", "no",  "f", "n", and "0" are all synonyms for "false"

  * "int"/other numeric values are simple, but must be numbers.
    Quote a leading space to distinguish negative numbers from options.

  * Singular "string" values for option "foo" defaulting to "bar":
    --foo=val     => val      ; clobbers
    --foo=        => ""       ; clears
    --foo+=val    => barval   ; appends
    --foo^=val    => valbar   ; prepends

  * Plural "strings" values for option "foo" defaulting to "A,B":
    --foo=val     => A,B,val  ; append
    --foo=        => A,B,""   ; append (an empty string)
    --foo+=val    => A,B,val  ; append
    --foo^=val    => val,A,B  ; prepend
    --foo-=A      => B        ; remove (0 or more) entries equal to "A"
  Multi-value syntaxes for option "foo" defaulting to "A,B":
    --foo,=       => {}       ; clears
    --foo,=,C,D   => A,B,C,D  ; append multi
    --foo,=/C/    => A,B,C,"" ; ditto (note trailing delimiter effect)
    --foo,=,      => A,B,""   ; ditto
    --foo,+=,C,D  => A,B,C,D  ; ditto
    --foo,^=,C,D  => C,D,A,B  ; prepend multi
    --foo,-=,A,B  => {}       ; removes multi (here, ends up empty)
    --foo,@=,C,D  => C,D      ; clobbering multi assignment
"""
