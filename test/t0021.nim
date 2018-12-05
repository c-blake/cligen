#[
KEY cligen object
https://github.com/c-blake/cligen/issues/30
]#

type App = ref object
  nim: string ## compiler to use
  srcFile: string ## script to run
  # non-doc comment: this won't appear in `help`
  showHeader: bool ## show informative compiler info
  other: string ## defaults to smthg inferred from other args

proc newApp(): auto=
  result = App(nim:"foo", srcFile:"bar", showHeader: false)
  result.other = result.nim & " FOOBAR"
  
proc main(app = newApp()) =
  echo app.repr

when isMainModule:
  import cligen
  dispatch(main) # help inferred from fields' documentation comments
