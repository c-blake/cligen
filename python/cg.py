import sys, os, re, argparse as ap, ast; E=os.environ.get; e=sys.stderr.write

def load(f): # CfFile [SECT] -> Expr(value=List(elts=[Name(id='SECT', ..)],..))
  try: t=ast.parse(f.read()) # Assign(targets=[Name(id='KEY', ..)], value=VAL),
  except: e("could not parse '%s' as Python\n" % f.name)
  true ,yes,on  = True ,True ,True      # Works for me but doesn't handle much.
  false,no ,off = False,False,False     # E.g., same name section merging, etc.
  section = "global"; sections = {}     # Any implicit [global] must be early
  sections[section] = sectionDict = {}
  for n in ast.walk(t):
    if isinstance(n, ast.Expr):         #File: [Section]
      section = n.value.elts[0].id
      sections[section] = sectionDict = {}  # Just clobber if name is the same
    elif isinstance(n, ast.Assign):     #File: key = val
      key = n.targets[0].id
      val = n.value.value if hasattr(n.value, "value") else \
              (eval(n.value.id) if hasattr(n.value, "id") else \
                (n.value.s if hasattr(n.value, "s") else \
                  (n.value.n if hasattr(n.value, "n") else "")))
      try   : sectionDict[key].append(val)
      except: sectionDict[key] = [val]
  return sections

taAliases = {}                          # ta = t)ext a)ttribute
taNames = { "off": "", "none": "",  # Regular but for -bold=22v21, -BLINK=25v26
  "bold":  "1",  "faint":  "2",  "italic": "3", "underline": "4",  "blink": "5",
 "-bold": "22", "-faint": "22", "-italic":"23","-underline":"24", "-blink":"25",
  "BLINK": "6", "inverse": "7", "hid": "8", "struck":    "9",       "over":"53",
 "-BLINK":"25","-inverse":"27","-hid":"28","-struck":   "29",      "-over":"55",
 "underdouble":"4:2", "undercurl":"4:3", "underdot":"4:4", "underdash":"4:5",
 "black"   : "30", "red"      : "31", "green"    : "32", "yellow"   : "33",#DkF
 "blue"    : "34", "purple"   : "35", "cyan"     : "36", "white"    : "37",
 "BLACK"   : "90", "RED"      : "91", "GREEN"    : "92", "YELLOW"   : "93",#LiF
 "BLUE"    : "94", "PURPLE"   : "95", "CYAN"     : "96", "WHITE"    : "97",
 "on_black": "40", "on_red"   : "41", "on_green" : "42", "on_yellow": "43",#DkB
 "on_blue" : "44", "on_purple": "45", "on_cyan"  : "46", "on_white" : "47",
 "on_BLACK":"100", "on_RED"   :"101", "on_GREEN" :"102", "on_YELLOW":"103",#LiB
 "on_BLUE" :"104", "on_PURPLE":"105", "on_CYAN"  :"106", "on_WHITE" :"107",
 "-fg"     : "39", "-bg"      : "49", "plain"    :  "0", "NONE": ""}
def taParse(s):
  result = ""
  if len(s) == 0: return result
  while s in taAliases: s = taAliases[s]
  try: result = taNames[s]
  except KeyError:
    if len(s) >= 2:
      s0 = s[0].upper()
      if   s0 == 'F': prefix = "38;"
      elif s0 == 'B': prefix = "48;"
      elif s0 == 'U': prefix = "58;"
      else          : prefix = ""
      if   len(s) <= 3: result = prefix + "5;" + str(232 + int(s[1:]))
      elif s[1] == 's': e("cg.py does not support cligen/colorScl\n")
      elif len(s) == 4: # Above, xt256 grey scl, Below xt256 6*6*6 color cube
        r = min(5, ord(s[1]) - ord('0'))
        g = min(5, ord(s[2]) - ord('0'))
        b = min(5, ord(s[3]) - ord('0'))
        result = prefix + "5;" & str(16 + 36*r + 6*g + b)
      elif len(s) == 7: # True color
        r = int(s[1:3], 16)
        g = int(s[3:5], 16)
        b = int(s[5:7], 16)
        result = prefix + "2;" + str(r) + ";" + str(g) + ";" + str(b)
    if len(result) == 0: raise ValueError('bad text attr spec "%s"' % s)
  return result

def taOn(spec, plain=False):
  if plain: return ""   # Build \e[$A;3$F;4$Bm for attr A,colr F,B
  cs = [taParse(word) for word in spec]
  return "\x1b[" + ";".join(cs) + "m" if len(cs) > 0 and "" not in cs else ""

def taOnOff(s, plain):
  on = ""; off = "" if plain else "\x1b[m"
  if ';' in s:
    cs = s.split(';')
    if len(cs) != 2: e("[color] values ';' must separate on/off pairs\n")
    on  = taOn(cs[0].strip().split(), plain)
    off = taOn(cs[1].strip().split(), plain)
  else:
    on  = taOn(s.split(), plain)
  return (on, off)

colorSection = {}
for k,vs in [("optKey",("optkeys","options", "optkey","option")),
 ("valType",("valtypes","valuetypes","types", "valtype","valuetype","type")),
 ("dflVal" ,("dflvals","defaultvalues", "dflval","defaultvalue")),
 ("descrip",("descrips", "descriptions", "paramdescriptions")),
 ("cmd"    ,("cmd", "command", "cmdname", "commandname")),
 ("doc"    ,("doc", "documentation", "overalldocumentation")),
 ("args"   ,("args", "arguments", "argsonlinewithcmd")),
 ("bad"    ,("bad", "errbad", "errorbad")),
 ("good"   ,("good", "errgood", "errorgood"))]:
  for v in vs: colorSection[v] = k

def apply(cf=dict(), path="", plain=False):
  try   : defs = load(open(path, "rb"))
  except: e("problem reading/parsing '%s'\n" % path); return
  kind, rend = {}, {}
  for k,v in defs.items():
    if len(v) == 0 and k.startswith("include__"):
      relTo = os.path.dirname(path) + '/'
      sub  = k[9:]
      subs = sub.split("__")    # Allow include__VAR_NAME__DEFAULT[__..IGNOR]
      if len(subs) > 0 and subs[0] == subs[0].upper():
        subp = E(subs[0], subs[1] if len(subs) > 1 else "")
      else: subp = sub
      apply(cf, subp if subp.startswith("/") else (relTo + subp), plain)
    else:                       #TODO Could perhaps also handle [layout]
      if k in ("global", "aliases"):
        for K,V in v.items():
          if K=="colors":
            for x in V: cs=x.split('=');taAliases[cs[0].strip()] = cs[1].strip()
      elif k in "color":
        if plain: continue
        for K,V in v.items():
          (on, off) = taOnOff(V[0], plain)
          try: cs = colorSection[K.lower()]; kind[cs] = (on, off)
          except: pass
      elif k in "render":
        if plain: continue
        for K,V in v.items():
          K = K.lower()
          (on, off) = taOnOff(V[0], plain)
          if   K=="singlestar": rend["singlestar"] = (on, off)
          elif K=="doublestar": rend["doublestar"] = (on, off)
          elif K=="triplestar": rend["triplestar"] = (on, off)
          elif K=="singlebquo": rend["singlebquo"] = (on, off)
          elif K=="doublebquo": rend["doublebquo"] = (on, off)
  cf["kind"] = kind; cf["rend"] = rend
  return cf

try:
  cgPath = E("CLIGEN", os.path.expanduser("~/.config/cligen"))
  if os.path.isdir(cgPath): cgPath += "/config"
  cf = apply({}, cgPath, "NO_COLOR" in os.environ)
except: e("\x1b[1mcg.py: PROBLEM WITH %s\x1b[m\n" % cgPath)

def uMark(s): # micro-mark is just font changing (-> SGR on terminals).
  if s is None: return s
  fs = [("triplestar",r"\*{3}"),("doublestar",r"\*{2}"),("singlestar",r"\*{1}"),
        ("doublebquo",r"\`{2}"),("singlebquo",r"\`{1}")]
  for key, pat in fs:
    try:
      on, off = cf["rend"][key]
      s = re.sub(pat + r'(.+?)' + pat, '%s\\1%s' % (on,off), s)
    except: pass
  return s

def tn(act): # t)ype n)ame
  n = getattr(act.type, '__name__', '') if act.type else ''
  if act.nargs == '*': n = '[%s]' % n   # +,? are also possible
  return n

C = ap.RawDescriptionHelpFormatter
class HelpFmt(ap.RawDescriptionHelpFormatter):
  wK = wT = wDV = 0 # Caller must set manually if not via merge()
  wKTDv = 42        # Total max width of Keys, Types, Def.Vals before wrapping
  def __init__(o,prog):super(C,o).__init__(prog,max_help_position=HelpFmt.wKTDv)
  def _format_action_invocation(o, act):
    if not act.option_strings: return super(C,o)._format_action_invocation(act)
    K,k = cf["kind"].get("optKey", ("", ""))
    T,t = cf["kind"].get("valType", ("", ""))
    D,d = cf["kind"].get("dflVal", ("", ""))
    f   = "%s%%-%ds%s %s%%-%ds%s %s%%-%ds%s" % \
          (K, HelpFmt.wK+4, k,  T, HelpFmt.wT, t,  D, HelpFmt.wDV, d)
    keys = ", ".join(act.option_strings)
    if len(keys) > 0: return \
      (f if HelpFmt.wK>0 else "%s %s %s") % (keys, tn(act),
        repr(act.default) if act.default != ap.SUPPRESS else "")
    return super(C,o)._format_action_invocation(act)
  def _split_lines(o, text, width):
    D1,D0 = cf["kind"].get("descrip", ("", "")) # Escapes For 1st&last POST-wrap
    result = super(C,o)._split_lines(uMark(text), width)
    result[0]  = D1 + result[0]; result[-1] = result[-1] + D0
    return result
  def _format_text(o, text): return super(C,o)._format_text(uMark(text))
  def _format_usage(o, usage, actions, groups, prefix):
    return super(C,o)._format_usage(uMark(usage), actions, groups, prefix)

def maxLen(xs): return 0 if len(xs) == 0 else max(len(x) for x in xs)

def Len(s): return sum(0 if ord(c) < 32 else 1 for c in s)
Esc = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
def printedLen(s):              # Ctrl-[H..M] => -1,8-ish,cursor motions..?
  return Len(Esc.sub('',s))if isinstance(s,str)or isinstance(s,bytes)else len(s)
ap.len = printedLen

def merge(p, varNm, cfNm, wKTDv): # vars(merge(p, "CONFIG_F", "F"))
  cfPath = E(varNm, os.path.expanduser("~/.config/" + cfNm))
  if os.path.exists(cfPath):
    with open(cfPath, "rb") as f:
      defs = {}                 # New default values from config file
      try: fileDefs = load(f)["global"]
      except: return
      for k,v  in fileDefs.items():
        for a in p._actions:    # Get action for this arg | skip
          if a.dest == k: act = a; break
        else: continue
        if isinstance(act,ap._StoreConstAction): # TOML cvts to Py types, but..
          if   isinstance(v, bool): defs[k] = v  #..bool flags go by vals in cf
          elif isinstance(v, str):               #..file not presence like CLI.
            if   v.lower() in ('true' , 'yes', '1', 'on' ): defs[k] = True
            elif v.lower() in ('false', 'no' , '0', 'off'): defs[k] = False
        else: defs[k] = v       # For other args, trust TOML's type conversion
      p.set_defaults(**defs)    # Set config values as defaults
  HelpFmt.wKTDv = wKTDv
  HelpFmt.wK  = max(maxLen(a.option_strings) for a in p._actions)
  HelpFmt.wT  = max(len(tn(a)) for a in p._actions)
  HelpFmt.wDV = max(len(repr(a.default)) if a.default != ap.SUPPRESS else 0
                        for a in p._actions)
  return vars(p.parse_args())   # Finally return parsed arguments as a dict

import inspect as I; AP = ap.ArgumentParser # All works in either py2 or py3
def dictBut(d, K=None): return d if K is None else {k: d[k] for k in d if k!=K}
def both(a, b): return a if b is None else (b if a is None else a + b)

def dispatch(func, help={}, short={}, types={}, wKTDv=42, **kw):
  if sys.version[0]=='2': b=I.getargspec(func);V=b.varargs;A=b.args;D=b.defaults
  else:
      b=I.getfullargspec(func); V=b.varargs; A=both(b.args, b.kwonlyargs)
      D=b.kwonlydefaults if b.kwonlydefaults is not None else {}
      if len(b.args)>0: D.update(zip(b.args, b.defaults))
  doc = I.getdoc(func)
  p = AP(formatter_class=HelpFmt, **dict(kw, description=doc)) \
    if "description" not in kw and doc else AP(formatter_class=HelpFmt, **kw)
  def a(nm, **kw):
    sk = short.get(nm, nm[0])
    if len(sk)>0: p.add_argument('-'+sk, "--"+nm, **kw)
    else        : p.add_argument("--" + nm, **kw)
  for i, nm in enumerate(A):
    if sys.version[0]=='2': dv = D[i]
    else: dv = D[nm]
    ty, nAr = types.get(nm, (type(dv), None)) #XXX store_true->toggle like Nim?
    if ty==type(True): a(nm, action='store_true', help=help.get(nm, "set "+nm))
    else: a(nm, type=ty, nargs=nAr, default=dv, help=help.get(nm, "set "+nm))
  if V is not None:    # Yank out of `merge` output; ap.REMAINDER is tail only
    p.add_argument(V, nargs='*', default=[], help=help.get(V, "set "+V))
  fn = func.__name__
  mrg = merge(p, "CONFIG_" + fn.upper(), fn, wKTDv)
  if sys.version[0] != '2':
      va = mrg.get(V)
      if va is not None and len(va)>0: return func(*va, **dictBut(mrg,V))
      else: return func(**dictBut(mrg, V))
  else: return func(*tuple([mrg[k] for k in A] + mrg.get(V, [])))
