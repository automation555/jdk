# --- V4L ---
if(NOT HAVE_V4L)
  set(CMAKE_REQUIRED_QUIET TRUE) # for check_include_file
  check_include_file(linux/videodev2.h HAVE_CAMV4L2)
  check_include_file(sys/videoio.h HAVE_VIDEOIO)
  if(HAVE_CAMV4L2 OR HAVE_VIDEOIO)
    set(HAVE_V4L TRUE)
    set(defs)
    if(HAVE_CAMV4L2)
      list(APPEND defs "HAVE_CAMV4L2")
    endif()
    if(HAVE_VIDEOIO)
      list(APPEND defs "HAVE_VIDEOIO")
    endif()
    ocv_add_external_target(v4l "" "" "${defs}")
  endif()
endif()

set(HAVE_V4L ${HAVE_V4L} PARENT_SCOPE)
