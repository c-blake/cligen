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

let signum* = {      # Sadly, not-const-able
  "NIL"   : 0.cint , #0 # FYI: Just adopting SIGNONE here, since 0 does nothing.
  "HUP"   : SIGHUP , #1 # Bind strings to numeric constants; A long history of
  "INT"   : SIGINT , #2 # people just using literal numbers here makes this set
  "QUIT"  : SIGQUIT, #3 # of 32 essentially as standard numerically their names.
  "ILL"   : SIGILL , #4
  "TRAP"  : SIGTRAP, #5
  "ABRT"  : SIGABRT, #6
  "BUS"   : SIGBUS , #7
  "FPE"   : SIGFPE , #8
  "KILL"  : SIGKILL, #9
  "USR1"  : SIGUSR1, #10
  "SEGV"  : SIGSEGV, #11
  "USR2"  : SIGUSR2, #12
  "PIPE"  : SIGPIPE, #13
  "ALRM"  : SIGALRM, #14
  "TERM"  : SIGTERM, #15
  "TKFLT" : 16.cint, #16 Archaic SIGSTKFLT; spelled weird so "ST" can => STOP
  "CHLD"  : SIGCHLD, #17  Alias newer BSD/POSIX "CHLD"..
  "CLD"   : SIGCHLD, #17 ..with AT&T SysV "CLD".
  "CONT"  : SIGCONT, #18
  "STOP"  : SIGSTOP, #19
  "TSTP"  : SIGTSTP, #20
  "TTIN"  : SIGTTIN, #21
  "TTOU"  : SIGTTOU, #22
  "URG"   : SIGURG , #23
  "XCPU"  : SIGXCPU, #24
  "XFSZ"  : SIGXFSZ, #25
  "VTALRM":SIGVTALRM,#26
  "PROF"  : SIGPROF, #27
  "WINCH" : 28.cint, #28 Any shell/term needs this; Should be added to stdlib.
  "POLL"  : SIGPOLL, #29
  "PWR"   : 30.cint, #30
  "SYS"   : SIGSYS , #31
  "UNUSED": 31.cint }.toCritBitTree

proc parseUnixSignal*(nameOrNumber: string): cint =
  ## Accepts numbers as-is & otherwise case-insensitively prefix-matches against
  ## a set of standard signal abbreviations with an optional "SIG" prefix.
  var sNo: int
  if parseInt(nameOrNumber, sNo) == 0:
    let s = nameOrNumber.toUpper
    let squery = if s.startsWith("SIG"): s[3..^1] else: s
    return signum.match(squery, "signal name").val
  cint(if sNo < 0: 0 else: sNo)
