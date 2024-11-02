## This is an ``include`` file used by ``cligen.nim`` proper to initialize the
## ``clCfg`` global.  Here we use only a parsecfg config file to do so.
when defined(nimHasWarningObservableStores):
  {.push warning[ObservableStores]: off.}

import std/[streams, parsecfg] # , os, tables # for standalone
when not declared(stderr): import std/syncio
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
  var rendOpts = initTable[string, string]()
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
          activeSection = sec
        else:                   
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
        of "sigpipe": c.sigPIPE = parseEnum[ClSIGPIPE](e.value.optionNormalize)
        else:
          stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
                       "Can only be \"colors\"\n"
      of "layout":
        case e.key.optionNormalize
        of "widthenv":               c.widthEnv    = e.value
        of "rowsep", "rowseparator": c.hTabRowSep  = e.value
        of "colgap", "columngap":    c.hTabColGap  = parseInt(e.value)
        of "minlast", "leastfinal":  c.hTabMinLast = parseInt(e.value)
        of "required", "val4req":    c.hTabVal4req = e.value
        of "cols", "columns":
          c.hTabCols.setLen 0
          for tok in e.value.split: c.hTabCols.add parseEnum[ClHelpCol](tok)
        of "nohelphelp", "skiphelphelp":
          c.noHelpHelp = e.value.optionNormalize in yes
        of "minstrquoting":
          c.minStrQuoting = e.value.optionNormalize in yes
        of "truedefault" : c.trueDefault  = e.value
        of "falsedefault": c.falseDefault = e.value
        of "wrapDoc"     : c.wrapDoc      = e.value.parseInt
        of "wrapTable"   : c.wrapTable    = e.value.parseInt
        else:
          stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
            "Expecting: rowseparator columngap leastfinal required columns " &
            "nohelphelp\n"
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
        if not plain:
          var on = ""; var off = textAttrOff
          if ';' in e.value:
            let c = e.value.split(';')
            if c.len != 2:
              stderr.write "[color] values ';' must separate on/off pairs\n"
            on  = textAttrOn(c[0].strip.split, plain)
            off = textAttrOn(c[1].strip.split, plain)
          else:
            on = textAttrOn(e.value.split, plain)
          case e.key.optionNormalize
          of "optkeys", "options", "switches", "optkey", "option", "switch":
            c.helpAttr["clOptKeys"] = on; c.helpAttrOff["clOptKeys"] = off
          of "valtypes", "valuetypes", "types", "valtype", "valuetype", "type":
            c.helpAttr["clValType"] = on; c.helpAttrOff["clValType"] = off
          of "dflvals", "defaultvalues", "dflval", "defaultvalue":
            c.helpAttr["clDflVal"]  = on; c.helpAttrOff["clDflVal"]  = off
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
          else:
            stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
              "Expecting: options types defaultvalues descriptions command" &
              " documentation arguments errorbad errorgood\n"
      of "render":
        case e.key.optionNormalize
        of "singlestar": rendOpts["singlestar"] = e.value
        of "doublestar": rendOpts["doublestar"] = e.value
        of "triplestar": rendOpts["triplestar"] = e.value
        of "singlebquo": rendOpts["singlebquo"] = e.value
        of "doublebquo": rendOpts["doublebquo"] = e.value
        else:
          stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
            "Expecting: singlestar, doublestar, triplestar, singlebquo," &
            " doublebquo\n"
      of "templates":
        case e.key.optionNormalize
        of "usehdr", "usageheader" : c.useHdr     = hl(e.value)
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

let cfNm = getEnv("CLIGEN",(let cg = getConfigDir()/"cligen";
                            if cg.dirExists: cg/cgConfigFileBaseName else: cg))
if cfNm.fileExists: clCfg.apply(cfNm, existsEnv("NO_COLOR"))
# Any given end CL user likely wants just one global system of color aliases.
# Default to leaving initial ones defined, but clear if an env.var says to.
if existsEnv("CLIGEN_COLORS_CLEAR"): textAttrAliasClear()

when defined(nimHasWarningObservableStores):
  {.pop.}
