## This is an ``include`` file used by ``cligen.nim`` proper to initialize the
## ``clCfg`` global.  Here we use only a TOML config file to do so.  You must
## add parsetoml to your compile setup via nimble install parsetoml or elsewise.

import std/[strformat, sequtils], parsetoml # , tables # for standalone
when not declared(stderr): import std/syncio
const cgConfigFileBaseName = "config.toml"

proc apply(c: var ClCfg, cfgFile: string, plain=false) =
  template hl(x): string = specifierHighlight(x, Whitespace, plain,
                                              keepPct=false, termInAttr=false)
  template E(a: varargs[string, `$`]) = stderr.write a
  template uk(k1, k2) = E &"{cfgFile}: unknown keyword {k2} in section [{k1}]\n"
  var rendOpts = initTable[string, string]()
  let tomlCfg = parsetoml.parseFile(cfgFile).getTable
  for k1, v1 in tomlCfg.pairs:
    case k1.toLowerAscii
    of "includes":
      let includeFiles = v1.getElems().mapIt(it.getStr)
      for f in includeFiles:
        if f == cfgFile: continue # disallow infinite loop
        var f = f
        if f == f.toUpperAscii(): f = f.getEnv
        if not f.startsWith('/'): f = cfgFile.parentDir/f
        if f.fileExists: c.apply(f, plain)
    of "global", "aliases":
      for k2, v2 in v1.getTable.pairs:
        case k2.toLowerAscii
        of "colors":
          for k3, v3 in v2.getTable.pairs: textAttrAlias(k3, v3.getStr.strip)
        of "sigpipe":c.sigPIPE = parseEnum[ClSIGPIPE](v2.getStr.optionNormalize)
        else: uk k1, k2
    of "layout":
      for k2, v2 in v1.getTable.pairs:
        case k2.toLowerAscii
        of "widthenv":               c.widthEnv    = v2.getStr
        of "rowsep", "rowseparator": c.hTabRowSep  = v2.getStr
        of "subsep", "subrowsep":    c.subRowSep   = v2.getStr
        of "colgap", "columngap":    c.hTabColGap  = v2.getInt
        of "minlast", "leastfinal":  c.hTabMinLast = v2.getInt
        of "required", "val4req":    c.hTabVal4req = v2.getStr
        of "cols", "columns":
          c.hTabCols.setLen 0
          for tok in v2.getElems.mapIt(it.getStr):
            c.hTabCols.add parseEnum[ClHelpCol](tok)
        of "nohelphelp", "skiphelphelp": c.noHelpHelp      = v2.getBool
        of "minstrquoting"             : c.minStrQuoting   = v2.getBool
        of "truedefaultstr"            : c.trueDefaultStr  = v2.getStr
        of "falsedefaultstr"           : c.falseDefaultStr = v2.getStr
        of "wrapdoc"                   : c.wrapDoc         = v2.getInt
        of "wraptable"                 : c.wrapTable       = v2.getInt
        else: uk k1, k2
    of "syntax":
      for k2, v2 in v1.getTable.pairs:
        case k2.toLowerAscii
        of "reqsep", "requireseparator": c.reqSep = v2.getBool
        of "sepchars", "separatorchars":
          c.sepChars = {}
          for ch in v2.getElems.mapIt(it.getStr[0]): c.sepChars.incl(ch)
        of "longprefixok": c.longPfxOk = v2.getBool
        of "stopprefixok": c.longPfxOk = v2.getBool
        else: uk k1, k2
    of "color":
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
          of "optkeys", "options", "switches", "optkey", "option", "switch":
            c.helpAttr["clOptKeys"] = on; c.helpAttrOff["clOptKeys"] = off
          of "valtypes", "valuetypes", "types", "valtype", "valuetype", "type":
            c.helpAttr["clValType"] = on; c.helpAttrOff["clValType"] = off
          of "dflvals", "defaultvalues", "dflval", "defaultvalue":
            c.helpAttr["clDflVal"] = on; c.helpAttrOff["clDflVal"] = off
          of "descrips", "descriptions", "paramdescriptions", "descrip",
             "description", "paramdescription":
            c.helpAttr["clDescrip"] = on; c.helpAttrOff["clDescrip"] = off
          of "cmd", "command", "cmdname", "commandname":
            c.helpAttr["cmd"] = on; c.helpAttrOff["cmd"] = off
          of "doc", "documentation", "overalldocumentation":
            c.helpAttr["doc"] = on; c.helpAttrOff["doc"] = off
          of "args", "arguments", "argsonlinewithcmd":
            c.helpAttr["args"] = on; c.helpAttrOff["args"] = off
          of "bad", "errbad", "errorbad":
            c.helpAttr["bad"] = on; c.helpAttrOff["bad"] = off
          of "good", "errgood", "errorgood":
            c.helpAttr["good"] = on; c.helpAttrOff["good"] = off
          else: uk k1, k2
    of "render":
      for k2, v2 in v1.getTable.pairs:
        case k2.toLowerAscii
        of "singlestar": rendOpts["singlestar"] = v2.getStr
        of "doublestar": rendOpts["doublestar"] = v2.getStr
        of "triplestar": rendOpts["triplestar"] = v2.getStr
        of "singlebquo": rendOpts["singlebquo"] = v2.getStr
        of "doublebquo": rendOpts["doublebquo"] = v2.getStr
        else: uk k1, k2
    of "templates":
      for k2, v2 in v1.getTable.pairs:
        let templStr = v2.getStr.strip
        case k2.toLowerAscii
        of "usageheader", "usehdr" : c.useHdr     = hl(templStr)
        of "usage", "use"          : c.use        = hl(templStr)
        of "usagemulti", "usemulti": c.useMulti   = hl(templStr)
        of "helpsyntax"            : c.helpSyntax = hl(templStr)
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
