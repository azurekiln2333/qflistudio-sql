cmake_minimum_required(VERSION 3.15)
project(qfli_sqlite_native LANGUAGES C CXX)
add_subdirectory(../runtime ${CMAKE_CURRENT_BINARY_DIR}/engine)
set(qfli_sqlite_native_bundled_libraries
  $<TARGET_FILE:qfli_sqlite> PARENT_SCOPE)
if(NOT QFLI_ORACLE_HOME AND NOT DEFINED ENV{QFLI_ORACLE_HOME})
  set(QFLI_ORACLE_HOME "${CMAKE_CURRENT_SOURCE_DIR}/../build/mysql/windows/mysql-8.4.6-winx64" CACHE PATH "Oracle server bundle")
endif()
add_subdirectory(../mysql/desktop ${CMAKE_CURRENT_BINARY_DIR}/mysql)
