import std/[strutils, bitops, math], cligen/[mslice, unsafeAddr]
type                                    # Map a float "intensity" to RGB colors
  UnitR*  = range[0.0 .. 1.0]
  Color3* = (UnitR, UnitR, UnitR)
  Scale*  = enum sGray    = "gray",     ## Grey scale black -> white
                 sHue     = "hue",      ## Ancient HSV system "everyone" knows
                 sWLen    = "wLen",     ## Close to a physical spectrum/rainbow
                 sPm3D    = "pm3d",     ## Popularized by OS/2PresMgr | Gnuplot
                 sViridis = "viridis"   ## Very popular, maps well to gray outs

proc gray(x: UnitR): UnitR = 0.15 + 0.7*x # Tries to keep top & bottom readable

proc hsv2rgb*(hsv: Color3): Color3 =
  ## Convert from hue-saturation-value to red-green-blue color system.
  let (h, s, v) = (hsv[0].float, hsv[1].float, hsv[2].float)
  if s == 0.0: (v.UnitR, v.UnitR, v.UnitR) else:
    let h6 = h*6.0
    let i = int(h6)
    let f = h6 - i.float
    let (p, q, t) = (v*(1.0 - s), v*(1.0 - s*f), v*(1.0 - s*(1.0 - f)))
    case i mod 6
    of 0: (v.UnitR, t.UnitR, p.UnitR)
    of 1: (q.UnitR, v.UnitR, p.UnitR)
    of 2: (p.UnitR, v.UnitR, t.UnitR)
    of 3: (p.UnitR, q.UnitR, v.UnitR)
    of 4: (t.UnitR, p.UnitR, v.UnitR)
    of 5: (v.UnitR, p.UnitR, q.UnitR)
    else: (0.UnitR, 0.UnitR, 0.UnitR)

proc waveLen(x, sat, val: UnitR): Color3 =
  var x = x * 0.78    # Lop off 22% of confusingly similar red-purple spectrum
  x = x - 0.085       # Rotate color wheel so pink=lowest & purple=highest ..
  if x < 0: x += 1.0  #..(which is reversed by `rgb` below).
  hsv2rgb (x.UnitR, sat, val)

proc viridis(x: UnitR): Color3 = # Viridis quantized to 1 cache line per channel
  const r = [0x44'u8,0x46, 0x47,0x47, 0x48,0x48, 0x48,0x47, 0x46,0x45,
    0x44,0x43, 0x41,0x3F, 0x3D,0x3C, 0x3A,0x38, 0x36,0x34, 0x32,0x30, 0x2E,0x2D,
    0x2B,0x29, 0x28,0x26, 0x25,0x24, 0x22,0x21, 0x20,0x1F, 0x1E,0x1E, 0x1F,0x20,
    0x22,0x25, 0x29,0x2E, 0x34,0x3A, 0x41,0x49, 0x51,0x59, 0x61,0x6A, 0x73,0x7D,
    0x87,0x91, 0x9C,0xA6, 0xB1,0xBB, 0xC6,0xD1, 0xDB,0xE6, 0xF0,0xF9]
  const g = [0x03'u8,0x09, 0x0F,0x15, 0x1A,0x1F, 0x24,0x29, 0x2E,0x33,
    0x38,0x3D, 0x41,0x46, 0x4B,0x4F, 0x53,0x58, 0x5C,0x60, 0x64,0x68, 0x6C,0x70,
    0x73,0x77, 0x7B,0x7F, 0x82,0x86, 0x8A,0x8E, 0x92,0x95, 0x99,0x9D, 0xA1,0xA4,
    0xA8,0xAC, 0xAF,0xB3, 0xB6,0xBA, 0xBD,0xC1, 0xC4,0xC7, 0xCA,0xCD, 0xD0,0xD2,
    0xD5,0xD7, 0xD9,0xDB, 0xDD,0xDE, 0xE0,0xE1, 0xE2,0xE4, 0xE5,0xE6]
  const b = [0x56'u8,0x5C, 0x62,0x67, 0x6C,0x70, 0x75,0x79, 0x7C,0x7F,
    0x82,0x84, 0x86,0x88, 0x89,0x8A, 0x8B,0x8C, 0x8D,0x8D, 0x8D,0x8E, 0x8E,0x8E,
    0x8E,0x8E, 0x8E,0x8E, 0x8E,0x8E, 0x8D,0x8D, 0x8C,0x8B, 0x8A,0x88, 0x87,0x85,
    0x83,0x81, 0x7F,0x7C, 0x79,0x75, 0x71,0x6D, 0x69,0x64, 0x5F,0x5A, 0x55,0x4F,
    0x48,0x42, 0x3B,0x34, 0x2D,0x27, 0x20,0x1B, 0x18,0x19, 0x1C,0x22]
  let i = int(63.0*x + 0.5) # Above down-sampled from gnuplot by average([0..3])
  const scl = 1.0 / 256.0   # Byte->frac converter
  (UnitR(r[i].float*scl), UnitR(g[i].float*scl), UnitR(b[i].float*scl))

proc rgb*(x: UnitR, scale=sWLen, sat=UnitR(0.7), val=UnitR(0.9)): Color3 =
  ## Map x to RGB for a variety of false color scales as specified by `scale`.
  ## Parameters `sat` & `val` may be ignored depending upon `scale`.
  let x1 = UnitR(1.0 - x)   # Most want a range from "cold"=low to "hot"=high.
  case scale:
  of sGray: (x1.gray, x1.gray, x1.gray)
  of sHue : hsv2rgb (x1, sat, val)
  of sWLen: waveLen x1, sat, val
  of sPm3D: (x.sqrt.UnitR, UnitR(x*x*x), max(0.0, min(1.0, sin(2*Pi*x))).UnitR)
  of sViridis: viridis x

proc scaledCompon*(x: float, lim: range[4..1024] = 256): int =
  min(lim - 1, int(x * lim.float + 0.5))

proc hex*(rgb: Color3, lim: range[5..1024] = 256): string =
  ## Produce a string RGB RRGGBB or RRRGGGBBB of hex RedGreenBlue as needed.
  ## This is useful for HTML|X11 color specification even w/10-bit HDR color.
  let dig = (fastLog2(lim) + 3) div 4
  result.add scaledCompon(rgb[0], lim).toHex(dig)
  result.add scaledCompon(rgb[1], lim).toHex(dig)
  result.add scaledCompon(rgb[2], lim).toHex(dig)

proc ttc*(rgb: Color3, lim: range[5..1024] = 256): string =
  ## Produce decimal R;G;B string for a Terminal True Color specification.
  result.add $scaledCompon(rgb[0], lim); result.add ';'
  result.add $scaledCompon(rgb[1], lim); result.add ';'
  result.add $scaledCompon(rgb[2], lim)

proc xt256*(rgb: Color3, lim: range[5..1024] = 256): string =
  ## Produce decimal string for xterm-256 6*6*6 color cube specification.
  let r = min(5, scaledCompon(rgb[0], 5)) # Round & clip to 0..5
  let g = min(5, scaledCompon(rgb[1], 5))
  let b = min(5, scaledCompon(rgb[2], 5))
  $(16 + 36*r + 6*g + b)

var doNotUse: int
proc parseColorScl*(s: MSlice | openArray[char] | string;
                    nParsed: var int=doNotUse): Color3 =
  ## Parse color scale like `<sclNmPfx>FLOAT[,..]` where <sclNmPfx> is the first
  ## letter of a scale name, FLOAT is 0..1 scale, & `[,..]` are optional params.
  ## `nParse` gets number of chars handled.  An eg. good spec is: "w.3,.7,.65"
  ## for 30% wLen at 70% saturation, 65% value. { Yes, this could be fancier. }
  nParsed = 0; var nTmp = 0
  if s.len >= 2:
    var (sat, val) = (0.7, 0.9) #TODO Centralize 0.7/0.9 defaults in globals?
    let c = s[0].toLowerAscii
    let scl = (if c == 'g': sGray elif c == 'h': sHue elif c == 'p': sPm3D elif
               c == 'v': sViridis else: sWLen)
    var t = MSlice(mem: s[1].unsafeAddr, len: s.len - 1)
    let x = t.parseFloat(nParsed); inc nParsed  # Account for s[0]
    if nParsed < s.len and s[nParsed] == ',':   # Account for ',' & update `t`
      inc nParsed; t.mem = s[nParsed].unsafeAddr; t.len = s.len - nParsed
      sat = t.parseFloat(nTmp); inc nParsed, nTmp # parse float & update `t`
      if nTmp < t.len and t[nTmp] == ',':         # Account for ',' & update `t`
        inc nParsed; t.mem = s[nParsed].unsafeAddr; t.len = s.len - nParsed
        val = t.parseFloat(nTmp); inc nParsed, nTmp # parse float & update
    result = rgb(x, scl, sat, val)      # Finally dispatch to `rgb`

when isMainModule:
  import cligen
  when not declared(stdout): import std/syncio
  proc colScl(ns=7..7, text="X", x = -1.0,sat=0.7,val=0.9, scales: seq[Scale]) =
    ## Color scale driver to test distinguishability & name/memorability; Egs.:
    ## `colorScl -n8 g h w p v`; Look@"color edges" in `colorScl -n6..17 w p v`.
    ## Test just one color with e.g. `colorScl -x.75 -s.7 -v.95 wLen|head -n1`.
    proc outp(p: string, scl: Scale; x, s, v: UnitR) =
      stdout.write p, ";", rgb(x, scl, s, v).ttc, "m", text, "\e[m"
    let nLoop = ns.b > ns.a
    for scl in (if scales.len > 0: scales else: @[sWLen]):
      for n in ns:
        if nLoop: stdout.write align($n, 2), " "
        if scales.len > 1: stdout.write $scl, ": ", if nLoop: "" else: "\n"
        for (p,s,v)in [("\e[40;38;2", 0.70, 0.90), ("\e[107;38;2", 0.70, 0.75),
                       ("\e[30;48;2", 0.60, 0.90), ("\e[97;48;2" , 0.70, 0.65)]:
          if x == -1.0: # ^^Fix BG, vary FG; then fix FG, vary BG^^
            for k in 0 ..< n: outp p, scl, k.float/(n - 1).float, s, v
          else: outp p, scl, x, sat, val # Fully user specified: ignore `ns`,s,v
          if not nLoop: stdout.write "\n"
          else: stdout.write ' '.repeat(ns.b - n)
        if nLoop: stdout.write "\n"
  dispatch colScl, help={"scales": "scale(s): (gray|hue|wLen|pm3D|viridis)...",
                         "ns": "range of scale sizes"}
