## This is an ``include`` file used by ``cligen.nim`` proper to initialize the
## ``clCfg`` global.  Here we use only a config file to do so.
import parsecfg, streams, cligen/humanUt

# Drive Nim stdlib parsecfg to apply .config/cligen|include files to `c`.
proc apply(c: var ClCfg, path: string, plain=false) =
  const yes = [ "t", "true" , "yes", "y", "1", "on" ]
  template hl(x): string = specifierHighlight(x, Whitespace, keepPct=false,
                                              termInAttr=false)
  let relTo = path.parentDir & '/'
  var f = newFileStream(path, fmRead)
  if f == nil: return
  var p: CfgParser
  open(p, f, path)
  while true:
    var e = p.next
    case e.kind
    of cfgEof: break
    of cfgSectionStart:
      if e.section.startsWith("include__"):
        let sub = e.section[9..^1]
        let subp = if sub == sub.toUpperAscii: getEnv(sub) else: sub
        c.apply(if subp.startsWith("/"): subp else: relTo & subp, plain)
    of cfgKeyValuePair, cfgOption:
      case e.key.optionNormalize
      of "colors":
        let cols = e.value.split('=')
        textAttrAlias(cols[0].strip, cols[1].strip)
      of "optkeys":
        if not plain: c.helpAttr["clOptKeys"] = textAttrOn(e.value.split)
      of "valtype":
        if not plain: c.helpAttr["clValType"] = textAttrOn(e.value.split)
      of "dflval" :
        if not plain: c.helpAttr["clDflVal"]  = textAttrOn(e.value.split)
      of "descrip":
        if not plain: c.helpAttr["clDescrip"] = textAttrOn(e.value.split)
      of "colorcmd":
        if not plain: c.helpAttr["colorCmd"] = textAttrOn(e.value.split)
      of "colordoc":
        if not plain: c.helpAttr["colorDoc"] = textAttrOn(e.value.split)
      of "colorargs":
        if not plain: c.helpAttr["colorArgs"] = textAttrOn(e.value.split)
      of "htabcols":
        c.hTabCols.setLen 0
        for tok in e.value.split: c.hTabCols.add parseEnum[ClHelpCol](tok)
      of "htabrowsep":  c.hTabRowSep = e.value
      of "htabcolgap":  c.hTabColGap = parseInt(e.value)
      of "htabminlast": c.hTabMinLast = parseInt(e.value)
      of "reqsep":      c.reqSep = e.value.optionNormalize in yes
      of "sepchars":    c.sepChars = {}; (for ch in e.value: c.sepChars.incl ch)
      of "usehdr":      c.useHdr   = hl(e.value)
      of "use":         c.use      = hl(e.value)
      of "usemulti":    c.useMulti = hl(e.value)
      else: stderr.write path & ":" & " unknown keyword " & e.key & "\n"
    of cfgError: echo e.msg
  close(p)

var cfNm = getEnv("CLIGEN", os.getConfigDir() & "cligen/config")
if cfNm.existsFile: clCfg.apply(move(cfNm), existsEnv("NO_COLOR"))
elif cfNm.endsWith("/config") and cfNm[0..^8].existsFile:
  clCfg.apply(cfNm[0..^8], existsEnv("NO_COLOR"))
# Any given end CL user likely wants just one global system of color aliases.
# Default to leaving initial ones defined, but clear if an env.var says to.
if existsEnv("CLIGEN_COLORS_CLEAR"): textAttrAliasClear()
