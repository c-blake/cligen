## This is a module of utility procs that might be more broadly useful than only
## cligen.nim activity.

import macros, strutils

proc containsParam*(fpars: NimNode, key: string): bool =
  for declIx in 1 ..< len(fpars):           #default for result = false
    let idefs = fpars[declIx]               #Must use similar logic to..
    for i in 0 ..< len(idefs) - 3:          #..formalParamExpand because
      if $idefs[i] == key: return true      #..`suppress` is itself one of
    if $idefs[^3] == key: return true       #..the symbol lists we check.

proc formalParamExpand*(fpars: NimNode, n: auto,
                        suppress: seq[string]= @[]): NimNode =
  ## a,b,..,c:type [maybe=val] --> a:type, b:type, ..., c:type [maybe=val]
  result = newNimNode(nnkFormalParams)
  result.add(fpars[0])                                  # just copy ret value
  for p in suppress:
    if not fpars.containsParam(p):
      error repr(n[0]) & " has no param matching `suppress` key \"" & p & "\""
  for declIx in 1 ..< len(fpars):
    let idefs = fpars[declIx]
    for i in 0 ..< len(idefs) - 3:
      if $idefs[i] notin suppress:
        result.add(newIdentDefs(idefs[i], idefs[^2]))
    if $idefs[^3] notin suppress:
      result.add(newIdentDefs(idefs[^3], idefs[^2], idefs[^1]))

proc formalParams*(n: NimNode, suppress: seq[string]= @[]): NimNode =
  ## Extract expanded formal parameter list from the return value of .getImpl
  for kid in n:
    if kid.kind == nnkFormalParams:
      return formalParamExpand(kid, n, suppress)
  error "formalParams requires a proc argument."
  return nil                #not-reached

proc findByName*(parNm: string, fpars: NimNode): int =
  ## formal param slot of named parameter
  result = -1
  if len(parNm) == 0: return
  for i in 1 ..< len(fpars):
    if $fpars[i][0] == parNm:
      result = i
      break
  if result == -1:
    warning("specified argument `" & parNm & "` not found")

proc collectComments*(buf: var string, n: NimNode, depth: int = 0) =
  ## Extract doc comments from the return value of .getImpl
  if n.len > 1:
    for kid in n: collectComments(buf, kid, depth + 1)
  else:
    if n.kind == nnkCommentStmt and depth < 4:
      if n.strVal.len != 0:
        buf.add(" ")
        buf.add(n.strVal)

proc toStrSeq*(strSeqInitializer: NimNode): seq[string] =
  ## Transform a literal @[ "a", .. ] into compile-time seq[string]
  result = newSeq[string]()
  if strSeqInitializer.len > 1:
    for kid in strSeqInitializer[1]:
      result.add($kid)

proc srcBaseName*(n: NimNode): NimNode =
  ## Get the base name of the source file being compiled as an nnkStrLit
  let fileParen = lineinfo(n)
  let slash = if rfind(fileParen, "/") < 0: 0 else: rfind(fileParen, "/") + 1
  let paren = rfind(fileParen, ".nim(") - 1
  newStrLitNode(if paren < 0: "??" else: fileParen[slash..paren])

proc paramPresent*(n: NimNode, kwArg: string): bool =
  ## Check if a particular keyword argument parameter is present
  for k in n:
    if k.kind == nnkExprEqExpr and k[0].strVal == kwArg:
      return true

proc paramVal*(n: NimNode, kwArg: string): NimNode =
  ## Get the FIRST RHS/value of a keyword argument/named parameter
  for k in n:
    if k.kind == nnkExprEqExpr and k[0].strVal == kwArg:
      return k[1]
  nil

proc newParam*(id: string, rhs: NimNode): NimNode =
  ## Construct a keyword argument/named parameter expression for passing
  return newNimNode(nnkExprEqExpr).add(ident(id), rhs)
