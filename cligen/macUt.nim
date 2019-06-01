## This is a module of utility procs that might be more broadly useful than only
## cligen.nim activity.

import macros, strutils, os

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

proc srcPath*(n: NimNode): string =
  let fileParen = lineinfo(n)
  fileParen[0 .. (rfind(fileParen, "(") - 1)]

proc srcBaseName*(n: NimNode, sfx=".nim"): NimNode =
  ## Get the base name of the source file being compiled as an nnkStrLit
  let base = lastPathPart(srcPath(n))
  let nSfx = sfx.len + 1
  newStrLitNode(if base.len < nSfx: "??" else: base[0..^nSfx])

proc srcData*(n: NimNode): string =
  ## The entire file contents of source defining ``n``.
  staticRead srcPath(n)

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

proc fromNimble*(field: string, nimbleContents: string): string =
  ## ``const x=staticRead "relPathToNimbleFile"; use fromNimble("version",x)``
  result = "unparsable nimble " & field
  for line in nimbleContents.split("\n"):
    if line.startsWith(field):
      let cols = line.split('=')
      result = cols[1].strip()[1..^2]
      break

proc versionFromNimble*(nimbleContents: string): string {.deprecated:
     "Deprecated since v0.9.31; use fromNimble(\"version\",..) instead."} =
  ## const foo = staticRead "relPathToDotNimbleFile"; use versionFromNimble(foo)
  fromNimble("version", nimbleContents)

proc summaryOfModule*(sourceContents: string): string =
  ## First paragraph of doc comment for module defining ``n` (or empty string);
  ## Used to default ``["multi",doc]``.
  for line in sourceContents.split("\n"):
    let ln = line.strip()
    if ln == "##" or not ln.startsWith("##"):
      break
    result = result & line[2..^1].strip() & " "
  if result.len > 0 and result[^1] == ' ':
    result.setLen(result.len - 1)
  if result.len > 0:
    result = result & "\n\n"

proc summaryOfModule*(n: NimNode): string =
  summaryOfModule(srcData(n))

macro docFromModuleOf*(sym: typed{nkSym}): untyped =
  ## Used to default ``["multi",doc=docFromModleOf(mySymbol)]``.
  newStrLitNode(summaryOfModule(sym))
