## This is a module of utility procs that might be more broadly useful than only
## cligen.nim activity.

import core/macros, std/[strutils, os]

proc maybeDestrop*(id: NimNode): NimNode =
  ## Used to remove stropping backticks \`\`, if present, from an ident node
  case id.kind
  of nnkAccQuoted: id[0] 
  of nnkSym: newIdentNode($id)
  else: id

proc findByName*(parId: NimNode, fpars: NimNode): int =
  ## formal param slot of named parameter
  result = -1
  if len($parId) == 0: return
  for i in 1 ..< len(fpars):
    if maybeDestrop(fpars[i][0]) == maybeDestrop(parId):
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

proc toString*(n: NimNode): string =
  ## Get compile-time string from a symbol or literal.
  if n.kind == nnkSym: n.getImpl.strVal else: $n

proc toStrIni*(c: range[0 .. 255]): NimNode =
  ## Transform a literal 'x' into string literal initializer "x"
  newStrLitNode($chr(c))

proc toStrSeq*(strSeqInitializer: NimNode): seq[string] =
  ## Transform a literal @[ "a", .. ] into compile-time seq[string]
  if strSeqInitializer.len > 1:
    for kid in strSeqInitializer[1]:
      result.add($kid)

proc toIdSeq*(strSeqInitializer: NimNode): seq[NimNode] =
  ## Get a compile-time ``seq[ident]`` from a symbol or literal @[ "a", .. ].
  if strSeqInitializer.kind == nnkSym:
    for n in strSeqInitializer.getImpl:
      result.add(ident(n.strVal))
  else:
    if strSeqInitializer.len > 1:
      for kid in strSeqInitializer[1]:
        result.add(ident($kid))

proc has*(ns: seq[NimNode], n: NimNode): bool =
  for e in ns:
    if eqIdent(e, n): return true

proc srcPath*(n: NimNode): string =
  let fileParen = lineInfo(n)
  fileParen[0 .. (rfind(fileParen, "(") - 1)]

proc srcBaseName*(n: NimNode, sfx=".nim"): NimNode =
  ## Get the base name of the source file being compiled as an nnkStrLit
  let base = extractFilename(srcPath(n))
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

proc fromNimble*(nimbleContents: string, field: string): string =
  ## ``const x=staticRead "relPathToNimbleFile"; use fromNimble("version",x)``
  result = "unparsable nimble " & field
  for line in nimbleContents.split("\n"):
    if line.startsWith(field):
      let cols = line.split('=')
      result = cols[1].strip()[1..^2]
      break

proc versionFromNimble*(nimbleContents: string): string {.deprecated:
     "Deprecated since v0.9.31; use fromNimble(...,\"version\") instead."} =
  ## const foo = staticRead "relPathToDotNimbleFile"; use versionFromNimble(foo)
  nimbleContents.fromNimble "version"

proc summaryOfModule*(sourceContents: string): string =
  ## First paragraph of doc comment for module defining ``n` (or empty string);
  ## Used to default ``["multi",doc]``.
  var mode = 0
  for line in sourceContents.split("\n"):
    let ln = line.strip()
    if mode == 0:       #scan for start of some substantive '##' doc comment
      if ln.len < 1: continue     # skip blanks and regular '#' comments
      if ln.startsWith("#") and not ln.startsWith("##"): continue
      if ln == "##": continue     # Also skip '^white##white$' emptie doc cmts
      mode = 1          #Something else.  Switch modes.
    if mode == 1:
      if ln == "##" or not ln.startsWith("##"):     # Done with initial block
        break
      result = result & line[2..^1].strip() & " "   # append doc cmt text
  result = result.strip()
  if result.len > 0:
    result = result & "\n\n"

proc summaryOfModule*(n: NimNode): string =
  summaryOfModule(srcData(n))

macro docFromModuleOf*(sym: typed{nkSym}): untyped =
  ## Used to default ``["multi",doc=docFromModuleOf(mySymbol)]``.
  newStrLitNode(summaryOfModule(sym))

macro docFromProc*(sym: typed{nkSym}): untyped =
  let impl = sym.getImpl
  if impl == nil: error "getImpl(" & $sym & ") returned nil."
  var cmtDoc = ""
  collectComments(cmtDoc, impl)
  newStrLitNode(strip(cmtDoc))

macro with*(ob: typed, fields: untyped, body: untyped): untyped =
  ## Usage ``with(ob, [ f1, f2, ... ]): body`` where ``ob`` is any expression
  ## with (unquoted) fields ``f1``,  ``f2``, ... and ``body`` is a code block
  ## which will be given templates named ``f1``, ``f2``, ... providing
  ## abbreviated access to ``ob``.
  result = newStmtList()
  for name in fields:
    result.add quote do:
      template `name`(): untyped {.used.} = `ob`.`name`
  result.add body
  result = nnkBlockStmt.newTree(newEmptyNode(), result)
