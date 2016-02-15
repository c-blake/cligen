when defined(windows):  # No idea if this even compiles on Windows
  import winlean, os
  type              #XXX stdlib terminal.nim should really just export all this
    SHORT = int16

    COORD = object
      X: SHORT
      Y: SHORT

    SMALL_RECT = object
      Left: SHORT
      Top: SHORT
      Right: SHORT
      Bottom: SHORT

    CONSOLE_SCREEN_BUFFER_INFO = object
      dwSize: COORD
      dwCursorPosition: COORD
      wAttributes: int16
      srWindow: SMALL_RECT
      dwMaximumWindowSize: COORD

  proc getConsoleScreenBufferInfo(hConsoleOutput: HANDLE,
    lpConsoleScreenBufferInfo: ptr CONSOLE_SCREEN_BUFFER_INFO): WINBOOL {.
      stdcall, dynlib: "kernel32", importc: "GetConsoleScreenBufferInfo".}

  proc terminalWidth*(h: Handle): int =
    var csbi: CONSOLESCREENBUFFERINFO
    if getConsoleScreenBufferInfo(h, addr csbi) != 0:
      return int(csbi.srWindow.Right - csbi.srWindow.Left + 1)
    return 0

  proc terminalWidth*(): int =
    var w: int = 0
    w = terminalWidth(getStdHandle(STD_INPUT_HANDLE))
    if w > 0: return w
    w = terminalWidth(getStdHandle(STD_OUTPUT_HANDLE))
    if w > 0: return w
    w = terminalWidth(getStdHandle(STD_ERROR_HANDLE))
    if w > 0: return w
    return 80
else:
  from posix      import open, close, ctermid, O_RDONLY
  from os         import getEnv
  from parseutils import parseInt

  var TIOCGWINSZ*{.importc, header: "<sys/ioctl.h>".}: culong

  type ioctl_winsize* {.importc: "struct winsize", header: "<termios.h>",
                        final, pure.} = object
    ws_row*, ws_col*, ws_xpixel*, ws_ypixel*: cushort

  proc ioctl*(fd: cint, request: culong, reply: ptr ioctl_winsize): int {.
    importc: "ioctl", header: "<stdio.h>", varargs.}

  proc terminalWidthIoctl*(fds: openArray[int]): int =
    var win: ioctl_winsize
    for fd in fds:
      if ioctl(cint(fd), TIOCGWINSZ, addr win) != -1:
        return int(win.ws_col)
    return 0

  var L_ctermid*{.importc, header: "<stdio.h>".}: cint

  proc terminalWidth*(): int =
    ## Decide on *some* terminal size
    var w = terminalWidthIoctl([0, 1, 2])   #Try standard file descriptors
    if w > 0: return w                      #...then try controlling tty
    var cterm = newString(L_ctermid)
    var fd = open(ctermid(cstring(cterm)), O_RDONLY)
    if fd != -1:
      w = terminalWidthIoctl([ int(fd) ])
    discard close(fd)
    if w > 0: return w
    var s = getEnv("COLUMNS")               #...then try standard env var
    if len(s) > 0 and parseInt(s, w) > 0 and w > 0:
      return w
    return 80                               #Finally default to venerable value

when isMainModule:
  echo terminalWidth()
