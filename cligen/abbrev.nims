switch("threads", "on")
if defined(tcc):
  switch("tlsEmulation", "on")
  if (NimMajor,NimMinor,NimPatch) >= (1,6,0): switch("mm", "markAndSweep")
  else: switch("gc", "markAndSweep")
  switch("passL","-lm")
