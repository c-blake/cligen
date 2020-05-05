# If you redefine these in some `cligen/helpTmpl` ahead of cligen-actual in your
# Nim path, it just needs to define: clUseHdr, clUse, clUseMulti

const clUseHdr* = "Usage:\n  " #Not used by dispatchMulti root help dump

const clUse* = "$command $args\n${doc}Options:\n$options"

# This next is just a local shared with clUseMulti default and Perlish.
const clUseMultiGeneral* = """
$command {-h|--help} or with no args at all prints this message.
$command --help-syntax gives general cligen syntax help.
Run "$command {help SUBCMD|SUBCMD --help}" to see help for just SUBCMD.
Run "$command help" to get *comprehensive* help.${ifVersion}"""

const clUseMulti* = """${doc}Usage:
  $command {SUBCMD}  [sub-command options & parameters]
where {SUBCMD} is one of:
$subcmds
""" & clUseMultiGeneral

const clUseMultiPerlish* = """NAME
  ${doc}USAGE
  $command {SUBCMD}  [sub-command options & parameters]

SUBCOMMANDS
$subcmds
""" & clUseMultiGeneral
