## ``argParse`` determines how string args are converted to native Nim types.
## ``argHelp`` explains this interpretation to a command-line user.  Define new
## overloads in-scope of ``dispatch`` to override these or support more types.

when (NimMajor,NimMinor,NimPatch) > (0,20,2):
  {.push warning[UnusedImport]: off.} # This is only for gcarc
import std/[strformat, sets, critbits, strutils], ./textUt, ./gcarc, ./parseopt3
from parseutils import parseBiggestInt, parseBiggestUInt, parseBiggestFloat
when (NimMajor,NimMinor,NimPatch) <= (0,19,8): import typetraits #$T -> system
when not declared(assert): import std/[assertions, formatfloat]; export `$`

type
  ClHelpContext* = enum clLongOpt,      ## a long option identifier
                        clSubCmd,       ## a sub-command name identifier
                        clEnumVal       ## an enum value name identifier
  Ce = CatchableError

proc helpCase*(inp: string, context: ClHelpContext = clSubCmd): string =
  ##This is a string-to-string transformer hook to convert whatever the native
  ##Nim code identifier casing is into a string for presentation to CLI users.
  ##By default it converts snake_case to kebab-case.
  result = inp.replace('_', '-')

proc nimEscape*(s: string, quote='"'): string =
  ## Until strutils gets a nimStringEscape that is not deprecated
  result = newStringOfCap(s.len + 2 + s.len shr 2)
  result.add(quote)
  for c in s: result.addEscapedChar(c)
  result.add(quote)

proc unescape*(s: string): string =
  ## Handles 1-byte octal, \[abtnvfre], and \xDD hex escapes
  let hexdigits = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
                    'a', 'b', 'c', 'd', 'e', 'f'}
  proc toHexDig(c: char): int =
    result = if c <= '9': ord(c) - ord('0') else: 10 + ord(c) - ord('a')
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    case s[i]
    of '\\':
      if i + 1 >= s.len:
        raise newException(ValueError, "incomplete escaped char")
      case s[i+1]
      of '0' .. '7': result.add(chr(ord(s[i+1]) - ord('0'))); inc(i, 2)
      of 'a': result.add(chr(0x07)); inc(i, 2)       #bell
      of 'b': result.add(chr(0x08)); inc(i, 2)       #backspace
      of 't': result.add(chr(0x09)); inc(i, 2)       #horizontal tab
      of 'n': result.add(chr(0x0A)); inc(i, 2)       #new line
      of 'v': result.add(chr(0x0B)); inc(i, 2)       #vertical tab
      of 'f': result.add(chr(0x0C)); inc(i, 2)       #form feed
      of 'r': result.add(chr(0x0D)); inc(i, 2)       #carriage ret
      of '\\': result.add(chr(0x5C)); inc(i, 2)      #backslash
      of 'e': result.add(chr(0x1B)); inc(i, 2)       #escape
      else:
        if i + 3 >= s.len:
          raise newException(ValueError, "incomplete 2-nibble hex escape")
        if s[i+1].toLowerAscii != 'x':
          raise newException(ValueError, "hex escape not of form \\xDD")
        let dhi = toLowerAscii(s[i+2])
        let dlo = toLowerAscii(s[i+3])
        if dhi notin hexdigits or dlo notin hexdigits:
          raise newException(ValueError, "non-hex escape: " & s[i..i+3])
        result.add(char(toHexDig(dhi)*16 + toHexDig(dlo)))
        inc(i, 4)
    else:
      result.add(s[i])
      inc(i, 1)

type ElementError* = object of ValueError
type ArgcvtParams* = object ## \
  ## Abstraction of non-param-type arguments to `argParse` and `argHelp`.
  ## Per-use data, then per-parameter data, then per-command/global data.
  key*: string        ## key actually used for this option
  val*: string        ## value actually given by user
  sep*: string        ## separator actually used (including before '=' text)
  parNm*: string      ## long option key/parameter name
  parRend*: string    ## long option key/parameter name rendered for help
  parSh*: string      ## short key for this option key
  parCount*: int      ## count of times this parameter has been invoked
  parReq*: int        ## flag indicating parameter is mandatory
  val4req*: string    ## how a required/mandatory default value is rendered
  help*: string       ## the whole help string, for parse errors
  msg*: string        ## Error message from a bad parse
  shortNoVal*: set[char]  ## short options keys where value may be omitted
  longNoVal*: seq[string] ## long option keys where value may be omitted

proc argKeys*(a: ArgcvtParams, argSep="="): string =
  ## `argKeys` generates the option keys column in help tables
  let hasShort = a.parSh.len > 0 and a.parSh != "\0"
  result = if hasShort: "-$1$3, --$2$3" % [ a.parSh, a.parRend, argSep ]
           else       : "--" & a.parRend & argSep

proc argDf*(a: ArgcvtParams, dv: string): string {.deprecated:
     "Deprecated since v0.9.24; No longer needed."} = dv
  ## Deprecated since v0.9.24; No longer needed.  Remove call.

# bools
proc argParse*(dst: var bool, dfl: bool, a: var ArgcvtParams): bool =
  if len(a.val) > 0:
    case a.val.toLowerAscii  # Like `strutils.parseBool` but we also accept t&f
    of "t", "true" , "yes", "y", "1", "on" : dst = true
    of "f", "false", "no" , "n", "0", "off": dst = false
    else:
      a.msg = "Bool option \"$1\" non-boolean argument (\"$2\")\n$3" %
              [ a.key, a.val, a.help ]
      return false
  else:               # No option arg => reverse of default (usually, ..
    dst = not dfl     #.. but not always this means false->true)
  return true

proc argHelp*(dfl: bool; a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys(argSep=""), "bool", $dfl ]
  if a.parSh.len > 0:
    a.shortNoVal.incl(a.parSh[0]) # bool can elide option arguments.
  a.longNoVal.add(move(a.parNm))  # So, add to *NoVal.

# cstrings
proc argParse*(dst: var cstring, dfl: cstring, a: var ArgcvtParams): bool =
  dst = cstring(a.val)
  return true

proc argHelp*(dfl: cstring; a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys, "string", nimEscape($dfl) ]

# chars
proc argParse*(dst: var char, dfl: char, a: var ArgcvtParams): bool =
  let val = unescape(a.val)
  if len(val) != 1:
    a.msg = "Bad value \"$1\" for single char param \"$2\"\n$3" %
            [ a.val, a.key, a.help ]
    return false
  dst = val[0]
  return true

proc argHelp*(dfl: char; a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys, "char", nimEscape($dfl, quote='\'') ]

# enums
proc argParse*[T: enum](dst: var T, dfl: T, a: var ArgcvtParams): bool =
  let valNorm = optionNormalize(a.val)      #Normalized strings
  var allNorm: seq[string]
  var allCanon: seq[string]                 #Canonical/helpCased string
  type EnumCanon[T] = tuple[e: T; canon: string]
  var crbt: CritBitTree[EnumCanon[T]]
  for e in low(T)..high(T):
    let canon = helpCase($e, clEnumVal)
    allCanon.add canon
    let norm = optionNormalize(canon)
    allNorm.add(norm)
    crbt[norm] = (e, canon)
  var ks: seq[string]; var es: seq[T]
  if valNorm in crbt:
    dst = crbt[valNorm].e; return true
  for v in crbt.valuesWithPrefix(valNorm):
    ks.add(v.canon)
    es.add(v.e)
  if ks.len == 1:
    dst = es[0]
    return true
  if ks.len > 1:
    a.msg = ("Ambiguous enum value prefix for option \"$1\".  " &
             "\"$2\" matches:\n  $3$4") % [ a.key, a.val, ks.join("\n  "),
            "\nRun with --help for more details.\n" ]
  else:
    let sugg = suggestions(valNorm, allNorm, allCanon)
    a.msg = "Bad enum value for option \"$1\". \"$2\" is not one of:\n  $3$4" %
            [ a.key, a.val, (allCanon.join(" ") & "\n\n"),
              ("Maybe you meant one of:\n  " & sugg.join("\n  ") &
               "\n\nRun with --help for more details.\n") ]
  return false

proc argHelp*[T: enum](dfl: T; a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys, $T, helpCase($dfl, clEnumVal) ]

# various numeric types
when not compiles(uint.low):
  proc low *[T: uint|uint64](x: typedesc[T]): T = cast[T](0)  #Missing in stdlib
  proc high*[T: uint|uint64](x: typedesc[T]): T = cast[T](-1) #Missing in stdlib

when not compiles($range[0'u32 .. 1'u32](0)):
  proc `$`(x: range and SomeUnsignedInt): string = $BiggestUInt(x)

template doArgParse[WideT: SomeNumber, T: SomeNumber](
    parse: untyped, dst: var T, dfl: T, a: var ArgcvtParams): bool =
  ## Auxilary template that performs `argParse` for numeric types.
  ## Required because we cannot store symbols `parseBiggestInt/UInt` in
  ## a `const` (limitation of Nim's VM). However, we can pass them to
  ## an `untyped` parameter of a template without problems.
  var parsed: WideT
  let stripped = strip(a.val)
  if len(stripped) == 0 or parse(stripped, parsed) != len(stripped):
    a.msg = "Bad value: \"$1\" for option \"$2\"; expecting $3\n$4" %
            [ a.val, a.key, $type(dfl), a.help ]
    false
  elif parsed < WideT(T.low) or parsed > WideT(T.high):
    a.msg = "Bad value: \"$1\" for option \"$2\"; out of range for $3\n$4" %
            [ a.val, a.key, $type(dfl), a.help ]
    false
  else:
    dst = T(parsed)
    true

proc argParse*[T: SomeNumber](dst: var T, dfl: T, a: var ArgcvtParams): bool =
  when T is SomeSignedInt:
    doArgParse[BiggestInt](parseBiggestInt, dst, dfl, a)
  elif T is SomeUnsignedInt:
    doArgParse[BiggestUInt](parseBiggestUInt, dst, dfl, a)
  else:
    doArgParse[BiggestFloat](parseBiggestFloat, dst, dfl, a)

proc argHelp*[T: SomeNumber](dfl: T, a: var ArgcvtParams): seq[string] =
  when T is range:
    when T is SomeInteger:
      when T is SomeUnsignedInt:
        type WideT = BiggestUInt
        const lb = $T.low
      else:
        type WideT = BiggestInt
        const lb =
          if WideT(T.low) < -1_000_000_000: ""
          else: $T.low
      const ub =
        if WideT(T.high) > WideT(1_000_000_000): ""
        else: $T.high
    else:
      const
        lb = $T.low
        ub = $T.high
    const typeName =
      if lb.len + ub.len > 0: lb & ".." & ub
      else: $T
  elif T is float64:
    const typeName = "float"
  else:
    const typeName = $T
  result = @[ a.argKeys, typeName, $dfl ]

proc argParse*[T,U](dst: var HSlice[T,U], dfl: HSlice[T,U],
                    a: var ArgcvtParams): bool =
  ## Parse i (=== i..i) | a:b (exclusive) | a..b (inclusive) into `HSlice`.
  ## Interpretation is up to caller/slice user.  Missing sides get 0.
  let inp = a.val.strip
  let fieldI = inp.split("..")
  let fieldX = inp.split(":")
  if fieldI.len > 2 or fieldX.len > 2 or inp.len == 0:
    a.msg="Bad value: \"$1\" for option \"$2\"; expecting $3|$3:$4|$3..$4\n$5" %
          [ a.val, a.key, $type(T), $type(U), a.help ]; return
  elif fieldX.len > 1:
    if fieldX[0].len > 0:
      a.val = fieldX[0]
      if not argParse(dst.a, dfl.a, a): return
    else: dst.a = 0
    if fieldX[1].len > 0:
      a.val = fieldX[1]
      if not argParse(dst.b, dfl.b, a): return
      dst.b -= 1                        # make exclusive
    else: dst.b = 0
  elif fieldI.len > 1:
    if fieldI[0].len > 0:
      a.val = fieldI[0]
      if not argParse(dst.a, dfl.a, a): return
    else: dst.a = 0
    if fieldI[1].len > 0:
      a.val = fieldI[1]
      if not argParse(dst.b, dfl.b, a): return
    else: dst.b = 0
  elif inp.len > 0:
    a.val = inp
    if not argParse(dst.a, dfl.a, a): return
    dst.b = U(dst.a)
  result = true

proc argHelp*[T,U](dfl: HSlice[T,U]; a: var ArgcvtParams): seq[string] =
  @[ a.argKeys, "Slice", $dfl.a & ".." & $dfl.b ]

## PARSING AGGREGATES (set,seq,..)
## ###############################
## This module also defines ``argParse``/``argHelp`` pairs for ``seq[T]`` and
## such (``set[T]``, ``HashSet[T]``, ..) with a full complement of operations:
## prepend (``^=``), subtract/delete (``-=``), as well as the usual append
## (``+=`` or just ``=|nothing`` as is customary, e.g. ``cc -Ipath1 -Ipath2``).
##
## ``string`` is treated more as a scalar variable by ``cligen`` in that an
## unqualified ``[:=<SPACE>]`` does an overwriting/clobbering assignment rather
## than adding to the end of the string, but ``+=`` effects the append if
## desired.  E.g., ``--foo=""`` overwrites the value to be an empty string,
## ``--foo+=""`` leaves it unaltered, and ``--foo^=new`` prepends ``"new"``.
##
## This module also supports a ``,``-prefixed family of enhanced Delimiter-
## Prefixed Separated Value operators that allow passing multiple slots to the
## above operators.  DPSV is like typical regex substitution syntax, e.g.,
## ``/old/new`` or ``%search%replace`` where the first ``char`` indicates the
## delimiter for the rest.  Delimiting is strict. (E.g., ``--foo,^=/old/new/``
## prepends 3 items ``@["old", "new", ""]`` to some ``foo: seq[string]``).
## Available only in the ``,``-family is also ``,@`` as in ``,@=<D>V1<D>V2...``
## which does a clobbering assignment of ``@["V1", "V2", ...]``.  *No delimiter*
## (i.e. ``"--foo,@="``) clips any aggregate to its empty version, e.g. ``@[]``.
##
## See more examples and comments in cligen/syntaxHelp.nim

proc argAggSplit*[T](a: var ArgcvtParams, split=true): seq[T] =
  ## Split DPSV (e.g. ",hello,world") into a parsed `seq[T]`.
  let toks = if split: a.val[1..^1].split(a.val[0]) else: @[ move(a.val) ]
  let old = a.sep; a.sep = ""     #can have agg[string] & want clobbers on elts
  for i, tok in toks:
    var parsed, default: T
    a.val = tok
    if not argParse(parsed, default, a):
      result.setLen(0); a.sep = old
      raise newException(ElementError, "Bad element " & $i)
    result.add(move(parsed))
  a.sep = old                     #probably don't need to restore, but eh.

proc getDescription*[T](defVal: T, parNm: string, defaultHelp: string): string =
  if defaultHelp.len > 0:         #TODO: what user explicitly set it to empty?
    return defaultHelp
  when T is seq:
    result = "append 1 val to " & parNm
  elif T is set or T is HashSet:
    result = "include 1 val in " & parNm
  elif T is enum:
    result = "select 1 " & $T
  else:
    result = "set " & parNm

proc formatHuman(a: string): string =
  const alphaNum = {'a'..'z'} + {'A'..'Z'} + {'0'..'9'}
  if a.len == 0:
    result.addQuoted ""
    return result
  var isSimple = true
  for ai in a:
    # avoid ~ which, if given via `--foo ~bar`, is expanded by shell
    # avoid , (would cause confusion bc of separator syntax)
    if ai notin alphaNum + {'-', '_', '.', '@', ':', '=', '+', '^', '/'}:
      isSimple = false
      break
  if isSimple:
    result = a
  else:
    result.addQuoted a

proc formatHuman(a: seq[string]): string =
  if a.len == 0: result = "{}"
  for i in 0..<a.len:
    if i>0:
      result.add ","
    result.add formatHuman(a[i])

const vowels = { 'a', 'e', 'i', 'o', 'u' }
proc plural*(word: string): string =
  ## Form English plural of word via all rules not needing a real dictionary.
  proc consOr1Vowel(s: string): bool =
    s[^1] notin vowels or (s.len > 1 and s[^2] notin vowels)
  let w = word.toLowerAscii
  if w.len < 2                            : word & "s"
  elif w[^1] == 'z'                       : word & "zes"
  elif w[^1] in { 's', 'x' }              : word & "es"
  elif w[^2..^1] == "sh"                  : word & "es"
  elif w[^2..^1] == "ch"                  : word & "es"   #XXX 'k'-sound => "s"
  elif w[^1] == 'y' and w[^2] notin vowels: word[0..^2] & "ies"
  elif w[^1] == 'f' and consOr1Vowel(w[0..^2]): word[0..^2] & "ves"
  elif w[^2..^1] == "fe" and consOr1Vowel(w[0..^3]): word[0..^3] & "ves"
  else                                    : word & "s"

proc argAggHelp*(dfls: seq[string]; aggTyp: string; typ, dfl: var string) =
  typ = if aggTyp == "array": plural(typ) else: fmt"{aggTyp}({typ})"
  # Note: this would print in Nim format: dfl = ($dfls)[1 .. ^1]
  dfl = formatHuman dfls

# seqs
proc argParse*[T](dst: var seq[T], dfl: seq[T], a: var ArgcvtParams): bool =
  result = true
  try:
    if a.sep.len <= 1:                      # No Sep|No Op => Append
      dst.add(argAggSplit[T](a, false))
      return
    if   a.sep == "+=": dst.add(argAggSplit[T](a, false))
    elif a.sep == "^=": dst = argAggSplit[T](a, false) & move(dst)
    elif a.sep == "-=":                     # Delete Mode
      let parsed = argAggSplit[T](a, false)[0]
      var dstNew: seq[T]
      for e in dst:                         # Slow algo,..
        if e != parsed: dstNew.add e        # ..but preserves order
      dst = dstNew
    elif a.val == "" and a.sep == ",=":     # just clobber
      dst.setLen(0)
    elif a.sep == ",@=":                    # split-clobber-assign
      dst = argAggSplit[T](a)
    elif a.sep == ",=" or a.sep == ",+=":   # split-append
      dst = move(dst) & argAggSplit[T](a)
    elif a.sep == ",^=":                    # split-prepend
      dst = argAggSplit[T](a) & move(dst)
    elif a.sep == ",-=":                    # split-delete
      let parsed = argAggSplit[T](a)
      var dstNew: seq[T]
      for e in dst:                         # Slow algo,..
        if e notin parsed: dstNew.add e     # ..but preserves order
      dst = dstNew
    else:
      a.msg = "Bad operator (\"$1\") for seq[T], param $2\n" % [a.sep, a.key]
      raise newException(ElementError, "Bad operator")
  except Ce:
    return false

proc argHelp*[T](dfl: seq[T], a: var ArgcvtParams): seq[string]=
  var typ = $T; var df: string
  var dflSeq: seq[string]
  for d in dfl: dflSeq.add($d)
  argAggHelp(dflSeq, "array", typ, df)
  result = @[ a.argKeys, typ, df ]

# strings -- after seq[T] just in case string=seq[char] may need that.
proc argParse*(dst: var string, dfl: string, a: var ArgcvtParams): bool =
  result = true
  if a.sep.len <= 1:                  # No|Only Separator => Clobber Assign
    dst = a.val; return               # Cannot fail to parse a string
  case a.sep[0]                       # char on command line before [=:]
  of '+', '&': dst.add(a.val)         # Append
  of '^': dst = a.val & dst           # Prepend
  else:
    a.msg = "Bad operator (\"$1\") for strings, param $2\n" % [a.sep, a.key]
    return false

proc argHelp*(dfl: string; a: var ArgcvtParams): seq[string] =
  result = @[ a.argKeys, "string", nimEscape(dfl) ]

# sets
proc incl*[T](dst: var set[T], toIncl: openArray[T]) =
  ## incl from an openArray; How can this NOT be in the stdlib?
  for e in toIncl: dst.incl(e)
proc excl*[T](dst: var set[T], toExcl: openArray[T]) =
  ## excl from an openArray; How can this NOT be in the stdlib?
  for e in toExcl: dst.excl(e)

proc argParse*[T](dst: var set[T], dfl: set[T], a: var ArgcvtParams): bool =
  result = true
  try:
    if a.sep.len <= 1:                      # No Sep|No Op => Append
      dst.incl(argAggSplit[T](a, false))
      return
    if   a.sep == "+=": dst.incl(argAggSplit[T](a, false))
    elif a.sep == "-=": dst.excl(argAggSplit[T](a, false))
    elif a.val == "" and a.sep == ",=":     # just clobber
      dst = {}
    elif a.sep == ",@=":                    # split-clobber-assign
      dst = {}; dst.incl(argAggSplit[T](a))
    elif a.sep == ",=" or a.sep == ",+=":   # split-include
      dst.incl(argAggSplit[T](a))
    elif a.sep == ",-=":                    # split-exclude
      dst.excl(argAggSplit[T](a))
    else:
      a.msg = "Bad operator (\"$1\") for set[T], param $2\n" % [a.sep, a.key]
      raise newException(ElementError, "Bad operator")
  except Ce:
    return false

proc argHelp*[T](dfl: set[T], a: var ArgcvtParams): seq[string]=
  var typ = $T; var df: string
  var dflSeq: seq[string]
  for d in dfl: dflSeq.add($d)
  argAggHelp(dflSeq, "set", typ, df)
  result = @[ a.argKeys, typ, df ]

# HashSets
when not declared(initHashSet):
  proc toHashSet[A](keys: openArray[A]): HashSet[A] = toSet[A](keys)

proc argParse*[T](dst: var HashSet[T], dfl: HashSet[T],
                  a: var ArgcvtParams): bool =
  result = true
  try:
    if a.sep.len <= 1:                      # No Sep|No Op => Append
      dst.incl(toHashSet(argAggSplit[T](a, false)))
      return
    if   a.sep == "+=": dst.incl(toHashSet(argAggSplit[T](a, false)))
    elif a.sep == "-=": dst.excl(toHashSet(argAggSplit[T](a, false)))
    elif a.val == "" and a.sep == ",=":     # just clobber
      dst.clear()
    elif a.sep == ",@=":                    # split-clobber-assign
      dst.clear(); dst.incl(toHashSet(argAggSplit[T](a)))
    elif a.sep == ",=" or a.sep == ",+=":   # split-include
      dst.incl(toHashSet(argAggSplit[T](a)))
    elif a.sep == ",-=":                    # split-exclude
      dst.excl(toHashSet(argAggSplit[T](a)))
    else:
      a.msg = "Bad operator (\"$1\") for HashSet[T], param $2\n" % [a.sep,a.key]
      raise newException(ElementError, "Bad operator")
  except Ce:
    return false

proc argHelp*[T](dfl: HashSet[T], a: var ArgcvtParams): seq[string]=
  var typ = $T; var df: string
  var dflSeq: seq[string]
  for d in dfl: dflSeq.add($d)
  argAggHelp(dflSeq, "hashset", typ, df)
  result = @[ a.argKeys, typ, df ]

#import tables # Tables XXX need 2D delimiting convention
#? intsets, lists, deques, queues, etc?
when isMainModule:
  assert plural("A") == "As"
  assert plural("book") == "books"
  assert plural("baby") == "babies"
  assert plural("toy") == "toys"
  assert plural("brush") == "brushes"
  assert plural("church") == "churches"
  assert plural("kiss") == "kisses"
  assert plural("box") == "boxes"
  assert plural("elf") == "elves"
  assert plural("wife") == "wives"
  assert plural("chief") == "chiefs"
  assert plural("oof") == "oofs"
