## This is a portability shim include file for when you want code to work
## without deprecation warnings under younger & older Nim compilers.  Just
## `include cligen/unsafeAdr` at the global scope before using unsafeAddr.
when (NimMajor,NimMinor,NimPatch) > (1,0,0):
  {.used.}
when (NimMajor,NimMinor) >= (1,9) and not declared(unsafeAddr):
  template unsafeAddr*(x): untyped = x.addr
