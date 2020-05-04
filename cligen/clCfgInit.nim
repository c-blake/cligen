## This is an ``include`` file used by ``cligen.nim`` proper to initialize the
## ``clCfg`` global.  Here we use only a config file to do so.
import std/[os, strutils, tables], cligen/humanUt

when defined(clCfgToml):
  import std/[strformat, sequtils]
  import parsetoml # nimble install parsetoml
  const cgConfigFileBaseName = "config.toml"
  include clCfgToml
else:
  import std/[streams, parsecfg]
  const cgConfigFileBaseName = "config"

  # Drive Nim stdlib parsecfg to apply .config/cligen|include files to `c`.
  proc apply(c: var ClCfg, path: string, plain=false) =
    const yes = [ "t", "true" , "yes", "y", "1", "on" ]
    var activeSection = "global"
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
        else:
          let sec = e.section.optionNormalize
          case sec
          of "global", "aliases", "layout", "syntax", "color", "templates":
            activeSection = sec
          else:
            stderr.write path & ":" & " unknown section " & e.section & "\n" &
              "Expecting: global aliases layout syntax color templates\n"
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
        of "templates":
          case e.key.optionNormalize
          of "usehdr", "usageheader":  c.useHdr   = hl(e.value)
          of "use", "usage":           c.use      = hl(e.value)
          of "usemulti", "usagemulti": c.useMulti = hl(e.value)
          else:
            stderr.write path & ":" & " unexpected setting " & e.key & "\n" &
              "Expecting: usageheader usage usagemulti\n"
        else: discard # cannot happen since we break early above
      of cfgError: echo e.msg
    close(p)

var cfNm = getEnv("CLIGEN", os.getConfigDir() / "cligen" / cgConfigFileBaseName)
if cfNm.existsFile: clCfg.apply(move(cfNm), existsEnv("NO_COLOR"))
elif cfNm.splitPath.head == "config" and (cfNm / cgConfigFileBaseName).existsFile:
  clCfg.apply(cfNm / cgConfigFileBaseName, existsEnv("NO_COLOR"))
# Any given end CL user likely wants just one global system of color aliases.
# Default to leaving initial ones defined, but clear if an env.var says to.
if existsEnv("CLIGEN_COLORS_CLEAR"): textAttrAliasClear()
