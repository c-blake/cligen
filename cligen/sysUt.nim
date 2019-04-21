proc `:=`*[T](x: var T, y: T): T =
  ## A assignment expression like convenience operator
  x = y
  x

iterator maybePar*(parallel: bool, a, b: int): int =
  ## if flag is true yield `` `||`(a,b) `` else ``countup(a,b)``.
  if parallel:
    for i in `||`(a, b): yield i
  else:
    for i in a .. b: yield i
