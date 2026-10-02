cmake_minimum_required(VERSION 3.20)
file(GET_RUNTIME_DEPENDENCIES EXECUTABLES "${SERVER}" LIBRARIES "${CLIENT}"
  RESOLVED_DEPENDENCIES_VAR dependencies UNRESOLVED_DEPENDENCIES_VAR unresolved
  PRE_EXCLUDE_REGEXES "linux-vdso"
  POST_EXCLUDE_REGEXES "/lib(c|m|pthread|dl|rt)\\.so" "/ld-linux[^/]*\\.so")
if(unresolved)
  message(FATAL_ERROR "Missing native MySQL dependencies: ${unresolved}")
endif()
foreach(dependency ${dependencies})
  file(COPY "${dependency}" DESTINATION "${DESTINATION}/lib" FOLLOW_SYMLINK_CHAIN)
endforeach()
