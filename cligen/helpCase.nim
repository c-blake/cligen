import strutils # replace

type
  ClHelpContext* = enum clLongOpt,      ## a long option identifier
                        clSubCmd,       ## a sub-command name identifier
                        clEnumVal       ## an enum value name identifier

proc helpCase*(inp: string, context: ClHelpContext = clSubCmd): string =
  ##This is a string-to-string transformer hook to convert whatever the native
  ##Nim code identifier casing is into a string for presentation to CLI users.
  ##By default it converts snake_case to kebab-case.
  result = inp.replace('_', '-')
