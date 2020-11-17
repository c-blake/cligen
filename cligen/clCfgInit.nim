## This is an ``include`` file used by ``cligen.nim`` proper to initialize the
## ``clCfg`` global.  Here we use only a parsecfg config file to do so.
when defined(nimHasWarningObservableStores):
  {.push warning[ObservableStores]: off.}

import std/[os, streams, parsecfg, tables]
const cgConfigFileBaseName = "config"

proc apply(c: var ClCfg, path: string, plain=false) =
  const yes = [ "t", "true" , "yes", "y", "1", "on" ]
  var activeSection = "global"
  template hl(x): string = specifierHighlight(x, Whitespace, plain,
                                              keepPct=false, termInAttr=false)
  let relTo = path.parentDir & '/'
  var f = newFileStream(path, fmRead)
  if f == nil: return
  var p: CfgParser
  var rendOpts: Table[string, string]
  open(p, f, path)
  while true:
    var e = p.next
    case e.kind
    of cfgEof: break
    of cfgSectionStart:
      if e.section.startsWith("include__"):
        let sub = e.section[9..^1]
        let subs = sub.split("__") # Allow include__VAR_NAME__DEFAULT[__..IGNOR]
        let subp = if subs.len>0 and subs[0] == subs[0].toUpperAscii:
                     getEnv(subs[0], if subs.len>1: subs[1] else: "") else: sub
        c.apply(if subp.startsWith("/"): subp else: relTo & subp, plain)
      else:
        let sec = e.section.optionNormalize
        case sec
        of "global","aliases","layout","syntax","color","render","templates":
          activeSection.setLen sec.len
          copyMem activeSection[0].addr, sec[0].unsafeAddr, sec.len
#         activeSection = sec;  # gc:arc bug Gen C code points `sec` at this
        else:                   # but then *also* calls destructor on sec.
          stderr.write path & ":" & " unknown section " & e.section & "\n" &
            "Expecting: global aliases layout syntax color render templates\n"
          break
    of cfgKeyValuePair, cfgOption:
      case activeSection
      of "global", "aliases":
        case e.key.optionNormalize #I realize this can be simpler, but as-is it
        of "colors":               #..allows darkBG symlink-> (lc|procs)/darkBG
          let cols = e.value.split('=')
          textAttrAlias(cols[0].strip, cols[1].strip)
        else:
          stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
                       "Can only be \"colors\"\n"
      of "layout":
        case e.key.optionNormalize
        of "rowsep", "rowseparator": c.hTabRowSep = e.value
        of "colgap", "columngap":    c.hTabColGap = parseInt(e.value)
        of "minlast", "leastfinal":  c.hTabMinLast = parseInt(e.value)
        of "cols", "columns":
          c.hTabCols.setLen 0
          for tok in e.value.split: c.hTabCols.add parseEnum[ClHelpCol](tok)
        else:
          stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
            "Expecting: rowseparator columngap leastfinal columns\n"
      of "syntax":
        case e.key.optionNormalize
        of "reqsep", "requireseparator":
          c.reqSep = e.value.optionNormalize in yes
        of "sepchars", "separatorchars":
          c.sepChars = {}; (for ch in e.value: c.sepChars.incl ch)
        of "longprefixok": c.longPfxOk = e.value.optionNormalize in yes
        of "stopprefixok": c.stopPfxOk = e.value.optionNormalize in yes
        else:
          stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
            "Expecting: requireseparator separatorchars\n"
      of "color":
        case e.key.optionNormalize
        of "optkeys", "options", "switches", "optkey", "option", "switch":
          if not plain: c.helpAttr["clOptKeys"] = textAttrOn(e.value.split)
        of "valtypes", "valuetypes", "types", "valtype", "valuetype", "type":
          if not plain: c.helpAttr["clValType"] = textAttrOn(e.value.split)
        of "dflvals", "defaultvalues", "dflval", "defaultvalue":
          if not plain: c.helpAttr["clDflVal"]  = textAttrOn(e.value.split)
        of "descrips", "descriptions", "paramdescriptions", "descrip", "description", "paramdescription":
          if not plain: c.helpAttr["clDescrip"] = textAttrOn(e.value.split)
        of "cmd", "command", "cmdname", "commandname":
          if not plain: c.helpAttr["cmd"] = textAttrOn(e.value.split)
        of "doc", "documentation", "overalldocumentation":
          if not plain: c.helpAttr["doc"] = textAttrOn(e.value.split)
        of "args", "arguments", "argsonlinewithcmd":
          if not plain: c.helpAttr["args"] = textAttrOn(e.value.split)
        else:
          stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
            "Expecting: options types defaultvalues descriptions command documentation arguments\n"
      of "render":
        case e.key.optionNormalize
        of "singlestar": rendOpts["singlestar"] = e.value
        of "doublestar": rendOpts["doublestar"] = e.value
        of "triplestar": rendOpts["triplestar"] = e.value
        of "singlebquo": rendOpts["singlebquo"] = e.value
        of "doublebquo": rendOpts["doublebquo"] = e.value
        else:
          stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
            "Expecting: singlestar, doublestar, triplestar, singlebquo, doublebquo\n"
      of "templates":
        case e.key.optionNormalize
        of "usehdr", "usageheader" :  c.useHdr    = hl(e.value)
        of "use", "usage"          : c.use        = hl(e.value)
        of "usemulti", "usagemulti": c.useMulti   = hl(e.value)
        of "helpsyntax"            : c.helpSyntax = hl(e.value)
        else:
          stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
            "Expecting: usageheader usage usagemulti\n"
      else: discard # cannot happen since we break early above
    of cfgError: echo e.msg
  close(p)
  if rendOpts.len > 0:
    let r = initRstMdSGR(rendOpts, plain)
    proc renderMarkup(m: string): string = r.render(m)
    c.render = renderMarkup

var cfNm = getEnv("CLIGEN", os.getConfigDir()/"cligen"/cgConfigFileBaseName)
if cfNm.fileExists: clCfg.apply(move(cfNm), existsEnv("NO_COLOR"))
elif cfNm.splitPath.head == "config" and (cfNm/cgConfigFileBaseName).fileExists:
  clCfg.apply(cfNm/cgConfigFileBaseName, existsEnv("NO_COLOR"))
# Any given end CL user likely wants just one global system of color aliases.
# Default to leaving initial ones defined, but clear if an env.var says to.
if existsEnv("CLIGEN_COLORS_CLEAR"): textAttrAliasClear()

when defined(nimHasWarningObservableStores):
  {.pop.}
