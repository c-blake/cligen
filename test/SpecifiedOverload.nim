import cligen

proc get(a=1) = discard
proc get(b=1.0) = discard

dispatch((proc (b: float))get)
