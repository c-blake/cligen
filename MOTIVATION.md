More Motivation For The Skeptical
=================================
There are so many CLI parser frameworks out there...Why do we need yet another?

This approach to command-line interfaces has some obvious Don't Repeat Yourself
("DRY", or relatedly "a few points of edit") properties.  It also has very nice
"loose coupling" properties.  `cligen` need not even be *present on the system*
unless you are compiling a CLI executable.  Similarly, wrapped routines need not
be in the same module, modifiable, or know anything about `cligen`.

This approach is great when you want to maintain an API and a CLI in parallel.
Mostly you can just update the API and a single line of help message.  Easy dual
API/CLI maintenance encourages preserving access to functionality via APIs/"Nim
import".  When so preserved, this then eases complex uses being driven by other
Nim programs rather than by shell scripts (once usage complexity makes scripting
language limitations annoying).

Besides complex (and varying!) shell quoting rules for parameter passing, native
Nim-calls are vastly more efficient than program invocation.  On modern CPUs, a
function call is typically 2-4 ns while launching a program can take 30..30,000
microseconds.  I.e.  program launch overhead can be 2500x to 15 million times
greater than function calls.  This overhead can add up if you wind up invoking
things on thousands to millions of files (or whatever parameters).  In the case
of a million launches of programs on 30ms network filesystems this could be 8
hours vs 2 milliseconds just in dispatch overhead.  (Nim even lets you tag procs
for in-client-code inlining making the ratio formally infinite, but this is just
one numerical example.)

Finally, and perhaps most importantly, this approach is "DRY for the brain".
The learning curve/cognitive load and even the extra program text for a CLI is
all about as minimal as possible.  Any potential CLI author *already knows* the
syntax for a "Nim proc declaration with default values" which serves as the
"declarative specification language" for the CLI in `cligen`.  Mostly they need
only learn what kind of proc is "command-like enough", minor controls for
`dispatch`, and the "binding/translation" between proc and command parameters.
The last is helped a lot by the auto-generated help message.  The minor controls
are gradual and "pickyness-driven".  There is a mentally "only pay for what you
use" kind of property.
