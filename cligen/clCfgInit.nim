## This is an ``include`` file used by ``cligen.nim`` proper to initialize the
## ``clCfg`` global.  Here we use only a parsecfg config file to do so.
when defined(nimHasWarningObservableStores):
  {.push warning[ObservableStores]: off.}

import std/[streams, parsecfg] # , os, tables # for standalone
when not declared(stderr): import std/syncio
const cgConfigFileBaseName = "config"
proc on(s: string, wordSeparators="_-", no=false): string {.noSideEffect.} =
  optionNormalize(s)

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
        of "global".on,"aliases".on,"layout".on,"syntax".on,"color".on,
           "render".on,"templates".on: activeSection = sec
        else:
          stderr.write path & ":" & " unknown section " & e.section & "\n" &
            "Expecting: global aliases layout syntax color render templates\n"
          break
    of cfgKeyValuePair, cfgOption:
      case activeSection
      of "global".on, "aliases".on:
        case e.key.optionNormalize #I realize this can be simpler, but as-is it
        of "colors".on:            #..allows darkBG symlink-> (lc|procs)/darkBG
          let cols = e.value.split('=')
          textAttrAlias(cols[0].strip, cols[1].strip)
        of "sigpipe".on: c.sigPIPE=parseEnum[ClSIGPIPE](e.value.optionNormalize)
        else:
          stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
                       "Can only be \"colors\" or \"sigpipe\"\n"
      of "layout".on:
        case e.key.optionNormalize
        of "widthEnv".on:                  c.widthEnv    = e.value
        of "rowSep".on, "rowSeparator".on: c.hTabRowSep  = e.value
        of "subSep".on, "subRowSep".on:    c.subRowSep   = e.value
        of "colGap".on, "columnGap".on:    c.hTabColGap  = parseInt(e.value)
        of "minLast".on, "leastFinal".on:  c.hTabMinLast = parseInt(e.value)
        of "required".on, "val4req".on:    c.hTabVal4req = e.value
        of "cols".on, "columns".on:
          c.hTabCols.setLen 0
          for tok in e.value.split: c.hTabCols.add parseEnum[ClHelpCol](tok)
        of "noHelpHelp".on, "skipHelpHelp".on:
          c.noHelpHelp = e.value.optionNormalize in yes
        of "minStrquoting".on:
          c.minStrQuoting = e.value.optionNormalize in yes
        of "trueDefaultStr".on : c.trueDefaultStr  = e.value
        of "falseDefaultStr".on: c.falseDefaultStr = e.value
        of "wrapDoc".on        : c.wrapDoc         = e.value.parseInt
        of "wrapTable".on      : c.wrapTable       = e.value.parseInt
        else:
          stderr.write path&":"&" unexpected setting "&e.key&"\nExpecting: "&
            "rowSep colGap minLast required cols noHelpHelp widthEnv\n  " &
            "minStrQuoting trueDefaultStr falseDefaultStr wrapDoc wrapTable\n"
      of "syntax".on:
        case e.key.optionNormalize
        of "sepChars".on, "separatorChars".on:
          c.sepChars = {}; (for ch in e.value: c.sepChars.incl ch)
        of "reqSep".on, "requireSeparator".on:
          c.reqSep = e.value.optionNormalize in yes
        of "argEndsOpts".on : c.argEndsOpts = e.value.optionNormalize in yes
        of "endOpts".on     : c.endOpts     = e.value.optionNormalize in yes
        of "onePerArg".on   : c.onePerArg   = e.value.optionNormalize in yes
        of "valued".on      : c.valued      = e.value.optionNormalize in yes
        of "longPrefixOk".on: c.longPfxOk   = e.value.optionNormalize in yes
        of "stopPrefixOk".on: c.stopPfxOk   = e.value.optionNormalize in yes
        of "exact".on       : c.exact       = e.value.optionNormalize in yes
        of "noShort".on     : c.noShort     = e.value.optionNormalize in yes
        of "or12".on        : c.or12        = e.value.optionNormalize in yes
        of "just1".on       : c.just1       = e.value.optionNormalize in yes
        else:
          stderr.write path&":"&" unexpected setting "&e.key&"\nExpecting: "&
            "requireSeparator separatorChars longPrefixOk stopPrefixOk\n" &
            "argEndsOpts endOpts onePerArg valued exact noShort or12 just1\n"
      of "color".on:
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
          of "optKeys".on, "options".on, "switches".on, "optKey".on,
             "option".on, "switch".on:
            c.helpAttr["clOptKeys"] = on; c.helpAttrOff["clOptKeys"] = off
          of "valTypes".on, "valueTypes".on, "types".on, "valType".on,
             "valueType".on, "type".on:
            c.helpAttr["clValType"] = on; c.helpAttrOff["clValType"] = off
          of "dflVals".on, "defaultValues".on, "dflval".on, "defaultValue".on:
            c.helpAttr["clDflVal"]  = on; c.helpAttrOff["clDflVal"]  = off
          of "descrips".on, "descriptions".on, "paramDescriptions".on,
             "descrip".on, "description".on, "paramDescription".on:
            c.helpAttr["clDescrip"] = on; c.helpAttrOff["clDescrip"] = off
          of "cmd".on, "command".on, "cmdName".on, "commandName".on:
            c.helpAttr["cmd"] = on; c.helpAttrOff["cmd"] = off
          of "doc".on, "documentation".on, "overallDocumentation".on:
            c.helpAttr["doc"] = on; c.helpAttrOff["doc"] = off
          of "args".on, "arguments".on, "argsOnLineWithCmd".on:
            c.helpAttr["args"] = on; c.helpAttrOff["args"] = off
          of "bad".on, "errBad".on, "errorBad".on:
            c.helpAttr["bad"] = on; c.helpAttrOff["bad"] = off
          of "good".on, "errGood".on, "errorGood".on:
            c.helpAttr["good"] = on; c.helpAttrOff["good"] = off
          else:
            stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
              "Expecting: options types defaultValues descriptions command" &
              " documentation arguments errorBad errorGood\n"
      of "render".on:
        case e.key.optionNormalize
        of "singleStar".on: rendOpts["singlestar"] = e.value
        of "doubleStar".on: rendOpts["doublestar"] = e.value
        of "tripleStar".on: rendOpts["triplestar"] = e.value
        of "singleBQuo".on: rendOpts["singlebquo"] = e.value
        of "doubleBQuo".on: rendOpts["doublebquo"] = e.value
        else:
          stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
            "Expecting: singleStar, doubleStar, tripleStar, singleBQuo," &
            " doubleBQuo\n"
      of "templates".on:
        case e.key.optionNormalize
        of "useHdr".on, "usageHeader".on : c.useHdr     = hl(e.value)
        of "use".on, "usage".on          : c.use        = hl(e.value)
        of "useMulti".on, "usageMulti".on: c.useMulti   = hl(e.value)
        of "helpSyntax".on            : c.helpSyntax = hl(e.value)
        else:
          stderr.write path&":"&" unexpected setting "&e.key&"\nExpecting: " &
            "useHdr,usageHeader use,usage useMulti,usageMulti helpSyntax\n"
      else: discard # cannot happen since we break early above
    of cfgError: echo e.msg
  close(p)
  if rendOpts.len > 0:
    let r = initRstMdSGR(rendOpts, plain)
    proc renderMarkup(m: string): string = r.render(m)
    c.render = renderMarkup

let cfNm = getEnv("CLIGEN",(let cg = getConfigDir()/"cligen";
                            if cg.dirExists: cg/cgConfigFileBaseName else: cg))
if cfNm.fileExists:
  clCfg.apply(cfNm, existsEnv("NO_COLOR") and
              getEnv("NO_COLOR") notin ["0", "no", "off", "false"] or
              getEnv("TERM", "") == "dumb")

# Any given end CL user likely wants just one global system of color aliases.
# Default to leaving initial ones defined, but clear if an env.var says to.
if existsEnv("CLIGEN_COLORS_CLEAR"): textAttrAliasClear()

when defined(nimHasWarningObservableStores):
  {.pop.}
