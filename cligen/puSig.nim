## Its own module not in `cligen/argcvt` since it's POSIX/Unix-only & few utils
## need it; Can be a nice UX for those who expect it.
##
## While a new Nim type `enum UnixSignal = sigHup = (SIGHUP, "HUP"), ...` with a
## new `kill` wrapper would be cleaner, for CL utils there is ancient tradition
## of just knowing & using signal numbers like "9".
##
## Meanwhile, for almost any other notional enum, users would NOT be expected to
## know "9".  So, a new "integer literal alternate" for all enums (or a Hex
## spelling for set[enum]!) seems of dubious value.
##
## The compromise here is to just use strings for CLs but also accept numbers.
## While we are at it, go fully case-insensitive since "hup" or "int" are easier
## to keystroke, introduce SysV CLD alias & "SIGNIL=0" & also accept an optional
## "sig" prefix allowing CLusers to be more explicit, e.g. in shell scripts.
##
## This may all seem like over-optimizing for CLuser expectations vs prog.lang.
## coherence, but whether in `procs find -akill` aka `pk` or elsewise, sending
## signals often coincides with rogue processes which can induce CLuser-level
## panic when people have the least patience with expectations being unmet.
##
## This code had been in `procs.nim`, but make sense here since there can be
## other reasons why a user might want a signal in a CLI, like `bu/etr` aborts.

import std/[parseutils, critbits, strutils, posix], cligen/textUt

template declOr(s, n): untyped = (when declared(s): s else: n.cint)
let signum* = {
  "NIL"   : 0.cint , #0 # FYI: Just adopting SIGNIL here, since 0 does nothing.
  "HUP"   : declOr(SIGHUP   , 1),
  "INT"   : declOr(SIGINT   , 2),
  "QUIT"  : declOr(SIGQUIT  , 3),
  "ILL"   : declOr(SIGILL   , 4),
  "TRAP"  : declOr(SIGTRAP  , 5),
  "ABRT"  : declOr(SIGABRT  , 6),
  "BUS"   : declOr(SIGBUS   , 7),
  "FPE"   : declOr(SIGFPE   , 8),
  "KILL"  : declOr(SIGKILL  , 9),
  "USR1"  : declOr(SIGUSR1  ,10), "U1": declOr(SIGUSR1  ,10),
  "SEGV"  : declOr(SIGSEGV  ,11),
  "USR2"  : declOr(SIGUSR2  ,12), "U2": declOr(SIGUSR2  ,12),
  "PIPE"  : declOr(SIGPIPE  ,13),
  "ALRM"  : declOr(SIGALRM  ,14),
  "TERM"  : declOr(SIGTERM  ,15),
  "TKFLT" : declOr(SIGSTKFLT,16), #Spelled so "ST" can => STOP
  "CHLD"  : declOr(SIGCHLD  ,17), # Alias newer BSD/POSIX "CHLD"..
  "CLD"   : declOr(SIGCHLD  ,17), #..with AT&T SysV "CLD".
  "CONT"  : declOr(SIGCONT  ,18),
  "STOP"  : declOr(SIGSTOP  ,19),
  "TSTP"  : declOr(SIGTSTP  ,20),
  "TTIN"  : declOr(SIGTTIN  ,21),
  "TTOU"  : declOr(SIGTTOU  ,22),
  "URG"   : declOr(SIGURG   ,23),
  "XCPU"  : declOr(SIGXCPU  ,24),
  "XFSZ"  : declOr(SIGXFSZ  ,25),
  "VTALRM": declOr(SIGVTALRM,26),
  "PROF"  : declOr(SIGPROF  ,27),
  "WINCH" : declOr(SIGWINCH ,28), #shells/terms need; stdlib should get
  "POLL"  : when defined osx: 7.int else: declOr(SIGPOLL, 29),
  "PWR"   : declOr(SIGPWR   ,30),
  "SYS"   : declOr(SIGSYS   ,31),
  "UNUSED": 32.cint }.toCritBitTree ##[ Bind strings to numeric constants; A
  history of folks just using literal numbers here makes common ones about as
  standard numerically their names. ]##

proc parseUnixSignal*(nameOrNumber: string): cint =
  ## Accepts numbers as-is & otherwise case-insensitively prefix-matches against
  ## a set of standard signal abbreviations with an optional "SIG" prefix.
  var sNo: int
  if parseInt(nameOrNumber, sNo) == 0:
    let s = nameOrNumber.toUpper
    let squery = if s.startsWith("SIG"): s[3..^1] else: s
    return signum.match(squery, "signal name").val
  cint(if sNo < 0: 0 else: sNo)
