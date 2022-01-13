#[ This text should be iterated upon until questions stop.  In particular, it's
   hard to know how much Nim (or beyond general shell) knowledge to assume. ]#

const syntaxHelp = """
BASIC CHEAT SHEET:
 * "--foo=val" is same as "--foo:val" and "--foo val".
 * Likewise with -f instead of --foo; in addition -fval|-f=val|-f:val also work
 * Long option,enum values and subcommands are "CLI-style-insensitive", meaning
   that the case of the 1st letter matters, but [_-] do not; --bar == --b_A-r.
 * Any unambiguous prefix is enough for long options, enum values & subcommands
 * "bool" values for flags "foo", "bar" with short options 'f', 'b':
     default value false: -f | --foo sets the flag to true
     default value true: -b | --bar sets the flag to false
     "-f=true" or "-b=true" always sets either to true (likewise for "false")
     synonyms for "true":  "on",  "yes", "t", "y", and "1"
     synonyms for "false": "off", "no",  "f", "n", and "0"
 * Multiple bool flags can combine: "-bfgVAL" means "-b -f -gVAL"
 * Non-option numbers < 0 are ok but must be distinguished from options by
   leading white space (usually needing command shell escaping or quotes).

Unlike most CLI frameworks, cligen directly supports managing PLURAL TYPES like
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
in ONE COMMAND PARAMETER.  DPSV is like regex substitution (eg., "/old/new" or
"%search%replace") where the first character says how to delimit the rest.
Delimiting is strict (a trailing delimiter means an empty slot).  No delimiter
("--foo,=") clears while ",@=" works like a clear followed by append.
 * Example multi-value updates for strings option "foo" defaulting to "A,B":
   --foo,=       => {}       ; clears the collection
   --foo,=,C,D   => A,B,C,D  ; append multi
   --foo,=/C/    => A,B,C,"" ; ditto (note trailing delimiter effect)
   --foo,=,      => A,B,""   ; ditto
   --foo,+=,C,D  => A,B,C,D  ; ditto
   --foo,^=,C,D  => C,D,A,B  ; prepend multi
   --foo,-=,A,B  => {}       ; removes multi (here, ends up empty)
   --foo,@=,C,D  => C,D      ; clobbering multi assignment
"""
