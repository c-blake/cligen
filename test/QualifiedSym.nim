import cligen

proc get(a=1) = discard

#XXX Does not seem to be a way to refer to some specific overload in Nim.
#Cannot cast[] since it's not a pointer type.
#func get(a: string) = discard 

dispatch(QualifiedSym.get)
