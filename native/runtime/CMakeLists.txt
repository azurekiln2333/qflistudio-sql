cmake_minimum_required(VERSION 3.15)
project(qfli_sqlite_runtime LANGUAGES C)

add_library(qfli_sqlite SHARED
  ../third_party/sqlite/sqlite3.c
  ../src/qfli_sql_bridge.c)
target_include_directories(qfli_sqlite PRIVATE
  ../third_party/sqlite ../src)
target_compile_features(qfli_sqlite PRIVATE c_std_99)
target_compile_definitions(qfli_sqlite PRIVATE
  SQLITE_THREADSAFE=1 SQLITE_DEFAULT_MEMSTATUS=0 SQLITE_DQS=0
  SQLITE_OMIT_LOAD_EXTENSION)
set_target_properties(qfli_sqlite PROPERTIES
  WINDOWS_EXPORT_ALL_SYMBOLS ON
  C_VISIBILITY_PRESET default)
if(WIN32)
  set_target_properties(qfli_sqlite PROPERTIES PREFIX "")
endif()
if(NOT WIN32)
  find_package(Threads REQUIRED)
  target_link_libraries(qfli_sqlite PRIVATE Threads::Threads m)
endif()
if(ANDROID)
  target_link_options(qfli_sqlite PRIVATE -Wl,-z,max-page-size=16384)
endif()
