import posix

var lastBadDev = 0.Dev
proc getxattr*(path: string, name: string, dev: Dev=0): int =
  proc getxattr(path:cstring; name:cstring; value:pointer; size:csize): csize {.
      importc: "getxattr", header: "sys/xattr.h".}
  if dev == lastBadDev: errno = EOPNOTSUPP; return -1
  result = getxattr(path.cstring, name.cstring, nil, 0).int
  if result == -1 and errno == EOPNOTSUPP:
    lastBadDev = dev
