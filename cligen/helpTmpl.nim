const clUse* = "$command $args\n$doc  Options(opt-arg sep :|=|spc):\n$options"
const clUsage* = "Usage:\n  " & clUse   #Use is for dispatchMulti else Usage

const clUseMulti* = """${doc}Usage:
  $command {SUBCMD}  [sub-command options & parameters]
where {SUBCMD} is one of:
$subcmds
$command {-h|--help} or with no args at all prints this message.
$command --help-syntax gives general cligen syntax help.
Run "$command {help SUBCMD|SUBCMD --help}" to see help for just SUBCMD.
Run "$command help" to get *comprehensive* help.$ifVersion"""
