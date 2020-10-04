import std/posix
type csize = uint

var lastBadDev = 0.Dev
when defined(linux):
  proc getxattr*(path: string, name: string, dev: Dev=0): int =
    proc getxattr(path: cstring; name: cstring; value: pointer;
        size: csize): csize {. importc: "getxattr", header: "sys/xattr.h".}
    if dev == lastBadDev: errno = EOPNOTSUPP; return -1
    result = getxattr(path.cstring, name.cstring, nil, 0).int
    if result == -1 and errno == EOPNOTSUPP:
      lastBadDev = dev
elif defined(freebsd):
  import strutils
  proc getxattr*(path: string, name: string, dev: Dev=0): int =
    const EA_NS_SYS = 2.cint
    proc extattr_get_file(path:cstring, attrnamespace: cint, attrnames: cstring,
                          data: cstring, nbytes: csize): csize {.
            importc: "extattr_get_file", header: "sys/extattr.h".}
    if dev == lastBadDev: errno = EOPNOTSUPP; return -1
    let nms = name.split('.')
    result = extattr_get_file(path.cstring, EA_NS_SYS, name.cstring, nil, 0).int
    if result == -1 and errno == EOPNOTSUPP:
      lastBadDev = dev
else:
  proc getxattr*(path: string, name: string, dev: Dev=0): int =
    errno = EOPNOTSUPP
    -1
