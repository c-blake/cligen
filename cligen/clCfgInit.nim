## This is an ``include`` file used by ``cligen.nim`` proper to initialize the
## ``clCfg`` global.

when defined(cgCfgToml):
  include cligen/clCfgInitToml # Trade parsetoml dependency for better documention
else:
  include cligen/clCfgInitDflt # Just use stdlib parsecfg

var cfNm = getEnv("CLIGEN")
if not cfNm.existsFile:
  let
    cfgDir = os.getConfigDir()/"cligen"
    configFileOptions = [cfgDir/"config",                # Parse using parsecfg
                         cfgDir/"config"/"config",       # Parse using parsecfg
                         cfgDir/"config.toml",           # Parse using parsetoml
                         cfgDir/"config"/"config.toml"]  # Parse using parsetoml
  cfNm = ""
  for f in configFileOptions:
    if f.existsFile:
      cfNm = f
      break
if cfNm != "":
  if cfNm.splitFile.ext == ".toml" and not defined(cgCfgToml):
    stderr.write("Config file $1 detected. Ensure that 'parsetoml' module is installed from nimble, compile with -d:cgCfgToml\n" % [cfNm])
    quit QuitFailure
  clCfg.apply(move(cfNm), existsEnv("NO_COLOR"))
# Any given end CL user likely wants just one global system of color aliases.
# Default to leaving initial ones defined, but clear if an env.var says to.
if existsEnv("CLIGEN_COLORS_CLEAR"): textAttrAliasClear()
