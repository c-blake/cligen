import cligen

proc get(a=1) = discard
proc put(b=2) = discard

dispatchMulti([QualifiedMulti.get, cmdName="get" ],
              [QualifiedMulti.put, cmdName="put", dispatchName="dispatchPut" ])
