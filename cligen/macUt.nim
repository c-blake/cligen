## This is a module of utility procs that might be more broadly useful than only
## cligen.nim activity.

import macros, strutils

proc findByName*(parId: NimNode, fpars: NimNode): int =
  ## formal param slot of named parameter
  result = -1
  if len($parId) == 0: return
  for i in 1 ..< len(fpars):
    if fpars[i][0] == parId:
      result = i
      break
  if result == -1:
    warning("specified argument `" & $parId & "` not found")

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
  if strSeqInitializer.len > 1:
    for kid in strSeqInitializer[1]:
      result.add($kid)

proc toIdSeq*(strSeqInitializer: NimNode): seq[NimNode] =
  ## Transform a literal @[ "a", .. ] into compile-time seq[ident]
  if strSeqInitializer.len > 1:
    for kid in strSeqInitializer[1]:
      result.add(ident($kid))

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

proc versionFromNimble*(nimbleContents: string): string =
  ## const foo = staticRead "relPathToDotNimbleFile"; use versionFromNimble(foo)
  result = "unparsable nimble version"
  for line in nimbleContents.split("\n"):
    if line.startsWith("version"):
      let cols = line.split('=')
      result = cols[1].strip()[1..^2]
      break

proc docFromNimble*(nimbleContents: string): string =
  ## const foo = staticRead "relPathToDotNimbleFile"; use docFromNimble(foo)
  result = "unparsable nimble description"
  for line in nimbleContents.split("\n"):
    if line.startsWith("description"):
      let cols = line.split('=')
      result = cols[1].strip()[1..^2]
      break

proc uriFromNimble*(nimbleContents: string): string =
  ## const foo = staticRead "relPathToDotNimbleFile"; use docFromNimble(foo)
  result = "unparsable nimble uri"
  for line in nimbleContents.split("\n"):
    if line.startsWith("uri"):
      let cols = line.split('=')
      result = cols[1].strip()[1..^2]
      break

proc authorFromNimble*(nimbleContents: string): string =
  ## const foo = staticRead "relPathToDotNimbleFile"; use docFromNimble(foo)
  result = "unparsable nimble uri"
  for line in nimbleContents.split("\n"):
    if line.startsWith("author"):
      let cols = line.split('=')
      result = cols[1].strip()[1..^2]
      break

proc docFromModule*(n: NimNode): string =
  ## First paragraph of doc comment for module defining ``n` (or empty string);
  ## Used to default ``["multi",doc]``.
  let fileParen = lineinfo(n)
  let path = fileParen[0 .. (rfind(fileParen, "(") - 1)]
  let data = staticRead path
  for line in data.split("\n"):
    let ln = line.strip()
    if ln == "##" or not ln.startsWith("##"):
      break
    result = result & line[2..^1].strip() & " "
  if result.len > 0 and result[^1] == ' ':
    result.setLen(result.len - 1)
  if result.len > 0:
    result = result & "\n\n"
