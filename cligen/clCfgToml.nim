## This is an ``include`` file used by ``cligen.nim`` proper to initialize the
## ``clCfg`` global.  Here we use only a TOML config file to do so.  You must
## add parsetoml to your compile setup via nimble install parsetoml or elsewise.

import std/[strformat, sequtils], parsetoml # , tables # for standalone
when not declared(stderr): import std/syncio
const cgConfigFileBaseName = "config.toml"
proc on(s: string, wordSeparators="_-", no=false): string {.noSideEffect.} =
  optionNormalize(s)

proc apply(c: var ClCfg, cfgFile: string, plain=false) =
  template hl(x): string = specifierHighlight(x, Whitespace, plain,
                                              keepPct=false, termInAttr=false)
  template E(a: varargs[string, `$`]) = stderr.write a
  template uk(k1, k2) = E &"{cfgFile}: unknown keyword {k2} in section [{k1}]\n"
  var rendOpts = initTable[string, string]()
  let tomlCfg = parsetoml.parseFile(cfgFile).getTable
  for k1, v1 in tomlCfg.pairs:
    case k1.toLowerAscii
    of "includes".on:
      let includeFiles = v1.getElems().mapIt(it.getStr)
      for f in includeFiles:
        if f == cfgFile: continue # disallow infinite loop
        var f = f
        if f == f.toUpperAscii(): f = f.getEnv
        if not f.startsWith('/'): f = cfgFile.parentDir/f
        if f.fileExists: c.apply(f, plain)
    of "global".on, "aliases".on:
      for k2, v2 in v1.getTable.pairs:
        case k2.toLowerAscii
        of "colors".on:
          for k3, v3 in v2.getTable.pairs: textAttrAlias(k3, v3.getStr.strip)
        of "sigpipe".on:c.sigPIPE=parseEnum[ClSIGPIPE] v2.getStr.optionNormalize
        else: uk k1, k2
    of "layout".on:
      for k2, v2 in v1.getTable.pairs:
        case k2.toLowerAscii
        of "widthEnv".on:                  c.widthEnv    = v2.getStr
        of "rowSep".on, "rowSeparator".on: c.hTabRowSep  = v2.getStr
        of "subSep".on, "subRowSep".on:    c.subRowSep   = v2.getStr
        of "colGap".on, "columnGap".on:    c.hTabColGap  = v2.getInt
        of "minLast".on, "leastFinal".on:  c.hTabMinLast = v2.getInt
        of "required".on, "val4req".on:    c.hTabVal4req = v2.getStr
        of "cols".on, "columns".on:
          c.hTabCols.setLen 0
          for tok in v2.getElems.mapIt(it.getStr):
            c.hTabCols.add parseEnum[ClHelpCol](tok)
        of "noHelpHelp".on, "skipHelpHelp".on: c.noHelpHelp      = v2.getBool
        of "minStrQuoting".on                : c.minStrQuoting   = v2.getBool
        of "trueDefaultStr".on               : c.trueDefaultStr  = v2.getStr
        of "falseDefaultStr".on              : c.falseDefaultStr = v2.getStr
        of "wrapDoc".on                      : c.wrapDoc         = v2.getInt
        of "wrapTable".on                    : c.wrapTable       = v2.getInt
        else: uk k1, k2
    of "syntax".on:
      for k2, v2 in v1.getTable.pairs:
        case k2.toLowerAscii
        of "sepChars".on, "separatorChars".on:
          c.sepChars = {}
          for ch in v2.getElems.mapIt(it.getStr[0]): c.sepChars.incl(ch)
        of "reqSep".on, "requireSeparator".on: c.reqSep = v2.getBool
        of "argEndsOpts".on : c.argEndsOpts = v2.getBool
        of "endOpts".on     : c.endOpts     = v2.getBool
        of "onePerArg".on   : c.onePerArg   = v2.getBool
        of "valued".on      : c.valued      = v2.getBool
        of "longPrefixOk".on: c.longPfxOk   = v2.getBool
        of "stopPrefixOk".on: c.stopPfxOk   = v2.getBool
        of "exact".on       : c.exact       = v2.getBool
        of "noShort".on     : c.noShort     = v2.getBool
        of "or12".on        : c.or12        = v2.getBool
        of "just1".on       : c.just1       = v2.getBool
        else: uk k1, k2
    of "color".on:
      if not plain:
        for k2, v2 in v1.getTable.pairs:
          let val = v2.getStr
          var on, off: string
          if ';' in val:
            let c = val.split(';')
            if c.len != 2: E "[color] values ';' must separate on/off pairs\n"
            on  = textAttrOn(c[0].strip.split, plain)
            off = textAttrOn(c[1].strip.split, plain)
          else:
            on = textAttrOn(val.strip.split, plain); off = textAttrOff
          case k2.toLowerAscii
          of "optKeys".on, "options".on, "switches".on, "optKey".on,
             "option".on, "switch".on:
            c.helpAttr["clOptKeys"] = on; c.helpAttrOff["clOptKeys"] = off
          of "valTypes".on, "valueTypes".on, "types".on, "valType".on,
             "valueType".on, "type".on:
            c.helpAttr["clValType"] = on; c.helpAttrOff["clValType"] = off
          of "dflVals".on, "defaultValues".on, "dflVal".on, "defaultValue".on:
            c.helpAttr["clDflVal"] = on; c.helpAttrOff["clDflVal"] = off
          of "descrips".on, "descriptions".on, "paramDescriptions".on,
             "descrip".on, "description".on, "paramDescription".on:
            c.helpAttr["clDescrip"] = on; c.helpAttrOff["clDescrip"] = off
          of "cmd".on, "command".on, "cmdName".on, "commandName".on:
            c.helpAttr["cmd"] = on; c.helpAttrOff["cmd"] = off
          of "doc".on, "documentation".on, "overallDocumentation".on:
            c.helpAttr["doc"] = on; c.helpAttrOff["doc"] = off
          of "args".on, "arguments".on, "argsOnlineWithCmd".on:
            c.helpAttr["args"] = on; c.helpAttrOff["args"] = off
          of "bad".on, "errBad".on, "errorBad".on:
            c.helpAttr["bad"] = on; c.helpAttrOff["bad"] = off
          of "good".on, "errGood".on, "errorGood".on:
            c.helpAttr["good"] = on; c.helpAttrOff["good"] = off
          else: uk k1, k2
    of "render".on:
      for k2, v2 in v1.getTable.pairs:
        case k2.toLowerAscii
        of "singleStar".on: rendOpts["singlestar"] = v2.getStr
        of "doubleStar".on: rendOpts["doublestar"] = v2.getStr
        of "tripleStar".on: rendOpts["triplestar"] = v2.getStr
        of "singleBQuo".on: rendOpts["singlebquo"] = v2.getStr
        of "doubleBQuo".on: rendOpts["doublebquo"] = v2.getStr
        else: uk k1, k2
    of "templates".on:
      for k2, v2 in v1.getTable.pairs:
        let templStr = v2.getStr.strip
        case k2.toLowerAscii
        of "usageHeader".on, "useHdr".on : c.useHdr     = hl(templStr)
        of "usage".on, "use".on          : c.use        = hl(templStr)
        of "usageMulti".on, "useMulti".on: c.useMulti   = hl(templStr)
        of "helpSyntax".on            : c.helpSyntax = hl(templStr)
        else: uk k1, k2
    else: E &"{cfgFile}: unknown keyword {k1}\n"
  if rendOpts.len > 0:
    let r = initRstMdSGR(rendOpts, plain)
    proc renderMarkup(m: string): string = r.render(m)
    c.render = renderMarkup

let cfNm = getEnv("CLIGEN",(let cg = getConfigDir()/"cligen";
                            if cg.dirExists: cg/cgConfigFileBaseName else: cg))
if cfNm.fileExists:
  clCfg.apply(cfNm, existsEnv("NO_COLOR") and
              getEnv("NO_COLOR") notin ["0", "no", "off", "false"])

# Any given end CL user likely wants just one global system of color aliases.
# Default to leaving initial ones defined, but clear if an env.var says to.
if existsEnv("CLIGEN_COLORS_CLEAR"): textAttrAliasClear()
