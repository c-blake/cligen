#[
This should maybe be re-written to be oriented toward a CLI user, not a
CLI author. { and re-written and written again until questions stop. }
In particular, it's hard to know how much Nim knowledge or beyond shell
programming knowledge in general to assume on the part of a CLI user.
]#

const syntaxHelp = """
BASIC CHEAT SHEET:
 * "--foo=val" is same as "--foo:val" and "--foo val".
 * Likewise with -f instead of --foo; in addition -fval is also possible.
 * Long option & enum names are "CLI-style-insensitive", meaning that only the
   case of the first letter matters otherwise; --foo is the same as --f_O-o.
 * "bool" values for flags "foo", "bar" with short options 'f', 'b':
     default value false: -f | --foo sets the flag to true
     default value true: -b | --bar sets the flag to false
     "-f=true" or "-b=true" always sets either to true (likewise for "false")
     synonyms for "true":  "on",  "yes", "t", "y", and "1"
     synonyms for "false": "off", "no",  "f", "n", and "0"
 * Multiple bool flags can combine: "-bf" means "-b -f"
 * Non-option numeric values are ok, but numbers < 0 must be distinguished
   from options by a leading space, usually requiring command shell quoting.

Unlike most CLI frameworks, cligen directly supports managing plural types like
"strings" with UPDATING OPERATIONS: prepend ("^="), subtract/delete ("-="), as
well as the usual append ("+=", "=", or repetition, as in "cc -Ipath1 -Ipath2").
 * Plural "strings" values for array[string] option "foo" with "A,B" default:
   --foo=val     => A,B,val  ; append
   --foo=        => A,B,""   ; append (an empty string)
   --foo+=val    => A,B,val  ; append
   --foo^=val    => val,A,B  ; prepend
   --foo-=A      => B        ; remove (0 or more) entries equal to "A"
 * Other plurals like sets on other base types work similarly.
 * Singular "string" is special;  For option "foo" defaulting to string "bar":
   --foo=val     => val      ; clobbers with "val"
   --foo=        => ""       ; clears the string
   --foo+=val    => barval   ; appends to the string
   --foo^=val    => valbar   ; prepends to the string

Plural types also support a ','-prefixed family of Delimiter-Prefixed Separated
Value (DPSV) operators that allow passing MULTIPLE SLOTS to the above operators
in ONE COMMAND PARAMETER.  DPSV is like typical regex substitution syntax (eg.,
"/old/new" or "%search%replace") where the first character of a value indicates
the delimiter for the rest.  Delimiting is strict (a trailing delimiter means
an empty slot).  No delimiter ("--foo,=") sets any plural to its empty version.
",@=" works like a set empty followed by an append.  I.e., "--foo,@=/V1/V2" is
just like "--foo,= --foo=/V1/V2".
 * Example multi-value updates for strings option "foo" defaulting to "A,B":
   --foo,=       => {}       ; clears
   --foo,=,C,D   => A,B,C,D  ; append multi
   --foo,=/C/    => A,B,C,"" ; ditto (note trailing delimiter effect)
   --foo,=,      => A,B,""   ; ditto
   --foo,+=,C,D  => A,B,C,D  ; ditto
   --foo,^=,C,D  => C,D,A,B  ; prepend multi
   --foo,-=,A,B  => {}       ; removes multi (here, ends up empty)
   --foo,@=,C,D  => C,D      ; clobbering multi assignment
"""
