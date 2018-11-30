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

Finally, and perhaps most importantly, this approach is "DRY for the brain".
The learning curve/cognitive load and even the extra program text for a CLI is
all about as minimal as possible.  Any potential CLI author *already knows* the
syntax for a Nim proc declaration with default values which serves as the
"declarative specification language" for the CLI in `cligen`.  Mostly they
just need to learn what kind of proc is "command-like enough", various minor
controls/arguments to `dispatch` to enhance the help message, and the
"binding/translation" between proc and command parameters.  The last is helped a
lot by the auto-generated help message and all the controls are gradual and
rather "pickyness-driven".  So, there is a mentally pay-as-you-go/only-pay-for-
what-you-use kind of property.
