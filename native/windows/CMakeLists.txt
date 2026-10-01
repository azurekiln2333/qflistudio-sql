cmake_minimum_required(VERSION 3.15)
project(qfli_sqlite_native LANGUAGES C)
add_subdirectory(../runtime ${CMAKE_CURRENT_BINARY_DIR}/engine)
set(qfli_sqlite_native_bundled_libraries
  $<TARGET_FILE:qfli_sqlite> PARENT_SCOPE)
