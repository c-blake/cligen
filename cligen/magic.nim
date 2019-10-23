type csize = uint
const
  so = static:
    var r = ""
    for f in [ "/usr/lib64/libmagic.so.1",
               "/usr/lib64/libmagic.so",
               "/usr/lib/libmagic.so.1",
               "/usr/lib/libmagic.so",
               "/usr/lib/x86_64-linux-gnu/libmagic.so.1",
               "/usr/lib/x86_64-linux-gnu/libmagic.so" ]:
      if gorgeEx("test -e " & f)[1] == 0:
        r = f
        break
    r
  cligenMagic {.booldefine.} = true
  haveMagic* = so.len > 0 and cligenMagic

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
    MAGIC_MIME*              = (MAGIC_MIME_TYPE or MAGIC_MIME_ENCODING)
    MAGIC_APPLE*             = 0x00000800
    MAGIC_EXTENSION*         = 0x01000000
    MAGIC_COMPRESS_TRANSP*   = 0x02000000
    MAGIC_NODESC*            = (MAGIC_EXTENSION or MAGIC_MIME or MAGIC_APPLE)
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
    MAGIC_NO_CHECK_BUILTIN*  = (MAGIC_NO_CHECK_COMPRESS or MAGIC_NO_CHECK_TAR or
        MAGIC_NO_CHECK_APPTYPE or MAGIC_NO_CHECK_ELF or MAGIC_NO_CHECK_TEXT or
        MAGIC_NO_CHECK_CDF or MAGIC_NO_CHECK_TOKENS or MAGIC_NO_CHECK_ENCODING)
        ## or MAGIC_NO_CHECK_SOFT
    MAGIC_SNPRINTB* = "\x7F\x10b\x00debug\x00b\x01symlink\x00b\x02compress\x00b\x03devices\x00b\x04mime_type\x00b\x05continue\x00b\x06check\x00b\apreserve_atime\x00b\braw\x00b\terror\x00b\nmime_encoding\x00b\vapple\x00b\fno_check_compress\x00b\cno_check_tar\x00b\x0Eno_check_soft\x00b\x0Fno_check_sapptype\x00b\x10no_check_elf\x00b\x11no_check_text\x00b\x12no_check_cdf\x00b\x13no_check_reserved0\x00b\x14no_check_tokens\x00b\x15no_check_encoding\x00b\x16no_check_reserved1\x00b\x17no_check_reserved2\x00b\x18extension\x00b\x19transp_compression\x00"
    ## Defined for backwards compatibility (renamed)
    MAGIC_NO_CHECK_ASCII*    = MAGIC_NO_CHECK_TEXT
    ## Defined for backwards compatibility; do nothing
    MAGIC_NO_CHECK_FORTRAN*  = 0x00000000
    MAGIC_NO_CHECK_TROFF*    = 0x00000000
    MAGIC_VERSION*           = 533

  type magic_t* = pointer # ptr magic_set

  proc magic_open*(a2: cint): magic_t {.importc:"magic_open".}
  proc magic_close*(a2: magic_t) {.importc:"magic_close".}
  proc magic_getpath*(a2: cstring; a3: cint): cstring {.
       importc:"magic_getpath".}
  proc magic_file*(a2: magic_t; a3: cstring): cstring {.importc:"magic_file".}
  proc magic_descriptor*(a2: magic_t; a3: cint): cstring {.
       importc:"magic_descriptor".}
  proc magic_buffer*(a2: magic_t; a3: pointer; a4: csize): cstring {.
       importc:"magic_buffer".}
  proc magic_error*(a2: magic_t): cstring {.importc:"magic_error".}
  proc magic_getflags*(a2: magic_t): cint {.importc:"magic_getflags".}
  proc magic_setflags*(a2: magic_t; a3: cint): cint {.importc:"magic_setflags".}
  proc magic_version*(): cint {.importc:"magic_version".}
  proc magic_load*(a2: magic_t; a3: cstring): cint {.importc:"magic_load".}
  proc magic_load_buffers*(a2: magic_t; a3: ptr pointer; a4: ptr csize;
                           a5: csize): cint {.importc:"magic_load_buffers".}
  proc magic_compile*(a2: magic_t; a3: cstring): cint {.
       importc:"magic_compile".}
  proc magic_check*(a2: magic_t; a3: cstring): cint {.
       importc:"magic_check".}
  proc magic_list*(a2: magic_t; a3: cstring): cint {.importc:"magic_list".}
  proc magic_errno*(a2: magic_t): cint {.importc:"magic_errno".}

  const
    MAGIC_PARAM_INDIR_MAX* = 0
    MAGIC_PARAM_NAME_MAX* = 1
    MAGIC_PARAM_ELF_PHNUM_MAX* = 2
    MAGIC_PARAM_ELF_SHNUM_MAX* = 3
    MAGIC_PARAM_ELF_NOTES_MAX* = 4
    MAGIC_PARAM_REGEX_MAX* = 5
    MAGIC_PARAM_BYTES_MAX* = 6
  proc magic_setparam*(a2: magic_t; a3: cint; a4: pointer): cint {.
       importc:"magic_setparam".}
  proc magic_getparam*(a2: magic_t; a3: cint; a4: pointer): cint {.
       importc:"magic_getparam".}
