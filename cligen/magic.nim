type csize = uint
const
  so = static:
    var r = ""
    for f in [ "/usr/lib64/libmagic.so.1",
               "/usr/lib64/libmagic.so",
               "/usr/lib/libmagic.so.1",
               "/usr/lib/libmagic.so",
               "/usr/lib/x86_64-linux-gnu/libmagic.so.1",
               "/usr/lib/x86_64-linux-gnu/libmagic.so",
               "/lib/aarch64-linux-gnu/libmagic.so.1",
               "/data/data/com.termux/files/usr/lib/libmagic.so" ]:
      if gorgeEx("test -e " & f)[1] == 0:
        r = f
        break
    when defined(macosx):
      const pat = "/usr/local/Cellar/libmagic/*/lib/libmagic.1.dylib"
      if r.len == 0:                          # This only works if there..
        if gorgeEx("test -e " & pat)[1] == 0: #..is exactly 1 pattern aka..
          r = gorgeEx("echo " & pat)[0]       #..version installed.
    r
  cligenMagic {.booldefine.} = true
  haveMagic* = so.len > 0 and cligenMagic

{.push hint[LineTooLong]:off.}
when haveMagic:
  {. passl: so .}
  const
    MAGIC_NONE*              = 0x00000000
    MAGIC_DEBUG*             = 0x00000001
    MAGIC_SYMLINK*           = 0x00000002
    MAGIC_COMPRESS*          = 0x00000004
    MAGIC_DEVICES*           = 0x00000008
    MAGIC_MIME_TYPE*         = 0x00000010
    MAGIC_CONTINUE*          = 0x00000020
    MAGIC_CHECK*             = 0x00000040
    MAGIC_PRESERVE_ATIME*    = 0x00000080
    MAGIC_RAW*               = 0x00000100
    MAGIC_ERROR*             = 0x00000200
    MAGIC_MIME_ENCODING*     = 0x00000400
    MAGIC_MIME*              = MAGIC_MIME_TYPE or MAGIC_MIME_ENCODING
    MAGIC_APPLE*             = 0x00000800
    MAGIC_EXTENSION*         = 0x01000000
    MAGIC_COMPRESS_TRANSP*   = 0x02000000
    MAGIC_NODESC*            = MAGIC_EXTENSION or MAGIC_MIME or MAGIC_APPLE
    MAGIC_NO_CHECK_COMPRESS* = 0x00001000
    MAGIC_NO_CHECK_TAR*      = 0x00002000
    MAGIC_NO_CHECK_SOFT*     = 0x00004000
    MAGIC_NO_CHECK_APPTYPE*  = 0x00008000
    MAGIC_NO_CHECK_ELF*      = 0x00010000
    MAGIC_NO_CHECK_TEXT*     = 0x00020000
    MAGIC_NO_CHECK_CDF*      = 0x00040000
    MAGIC_NO_CHECK_TOKENS*   = 0x00100000
    MAGIC_NO_CHECK_ENCODING* = 0x00200000
    ## No built-in tests; only consult the magic file
    MAGIC_NO_CHECK_BUILTIN*  = MAGIC_NO_CHECK_COMPRESS or MAGIC_NO_CHECK_TAR or
        MAGIC_NO_CHECK_APPTYPE or MAGIC_NO_CHECK_ELF or MAGIC_NO_CHECK_TEXT or
        MAGIC_NO_CHECK_CDF or MAGIC_NO_CHECK_TOKENS or MAGIC_NO_CHECK_ENCODING
        ## or MAGIC_NO_CHECK_SOFT
    MAGIC_SNPRINTB* = "\x7F\x10b\x00debug\x00b\x01symlink\x00b\x02compress\x00b\x03devices\x00b\x04mime_type\x00b\x05continue\x00b\x06check\x00b\apreserve_atime\x00b\braw\x00b\terror\x00b\nmime_encoding\x00b\vapple\x00b\fno_check_compress\x00b\cno_check_tar\x00b\x0Eno_check_soft\x00b\x0Fno_check_sapptype\x00b\x10no_check_elf\x00b\x11no_check_text\x00b\x12no_check_cdf\x00b\x13no_check_reserved0\x00b\x14no_check_tokens\x00b\x15no_check_encoding\x00b\x16no_check_reserved1\x00b\x17no_check_reserved2\x00b\x18extension\x00b\x19transp_compression\x00"
    ## Defined for backwards compatibility (renamed)
    MAGIC_NO_CHECK_ASCII*    = MAGIC_NO_CHECK_TEXT
    ## Defined for backwards compatibility; do nothing
    MAGIC_NO_CHECK_FORTRAN*  = 0x00000000
    MAGIC_NO_CHECK_TROFF*    = 0x00000000
    MAGIC_VERSION*           = 533

  type magic_t* = pointer # ptr magic_set; Opaque struct in the C magic.h

  proc magic_open*(flags: cint): magic_t {.importc.}
  proc magic_close*(m: magic_t) {.importc.}
  proc magic_getpath*(magicFile: cstring; action: cint): cstring {.importc.}
  proc magic_file*(m: magic_t; inName: cstring): cstring {.importc.}
  proc magic_descriptor*(m: magic_t; fd: cint): cstring {.importc.}
  proc magic_buffer*(m: magic_t; buf: pointer; nb: csize): cstring {.importc.}
  proc magic_error*(m: magic_t): cstring {.importc.}
  proc magic_getflags*(m: magic_t): cint {.importc.}
  proc magic_setflags*(m: magic_t; flags: cint): cint {.importc.}
  proc magic_version*(): cint {.importc.}
  proc magic_load*(m: magic_t; magicFile: cstring): cint {.importc.}
  proc magic_load_buffers*(m: magic_t; bufs: ptr pointer; sizes: ptr csize;
                           nbufs: csize): cint {.importc.}
  proc magic_compile*(m: magic_t; magicFile: cstring): cint {.importc.}
  proc magic_check*(m: magic_t; magicFile: cstring): cint {.importc.}
  proc magic_list*(m: magic_t; magicFile: cstring): cint {.importc.}
  proc magic_errno*(m: magic_t): cint {.importc.}

  const MAGIC_PARAM_INDIR_MAX* = 0
  const MAGIC_PARAM_NAME_MAX* = 1
  const MAGIC_PARAM_ELF_PHNUM_MAX* = 2
  const MAGIC_PARAM_ELF_SHNUM_MAX* = 3
  const MAGIC_PARAM_ELF_NOTES_MAX* = 4
  const MAGIC_PARAM_REGEX_MAX* = 5
  const MAGIC_PARAM_BYTES_MAX* = 6
  proc magic_setparam*(m: magic_t; param: cint; val: pointer): cint {.importc.}
  proc magic_getparam*(m: magic_t; param: cint; val: pointer): cint {.importc.}
{.pop.}
