## This is a module of utility procs that might be more broadly useful than only
## cligen.nim activity.

import macros, strutils

proc findByName*(parNm: string, fpars: NimNode): int =
  ## formal param slot of named parameter
  result = -1
  if len(parNm) == 0: return
  let parId = ident(parNm)
  for i in 1 ..< len(fpars):
    if fpars[i][0] == parId:
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
  let kwArgId = ident(kwArg)
  for k in n:
    if k.kind == nnkExprEqExpr and k[0] == kwArgId:
      return true

proc paramVal*(n: NimNode, kwArg: string): NimNode =
  ## Get the FIRST RHS/value of a keyword argument/named parameter
  let kwArgId = ident(kwArg)
  for k in n:
    if k.kind == nnkExprEqExpr and k[0] == kwArgId:
      return k[1]
  nil

proc newParam*(id: string, rhs: NimNode): NimNode =
  ## Construct a keyword argument/named parameter expression for passing
  return newNimNode(nnkExprEqExpr).add(ident(id), rhs)
