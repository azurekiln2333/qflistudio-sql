cmake_minimum_required(VERSION 3.18)
project(qfli_sql_validation_tests LANGUAGES C CXX)

enable_testing()
set(CMAKE_C_STANDARD 99)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(SQL_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../..")
set(VALIDATION_ROOT "${SQL_ROOT}/ohos/entry/src/main/cpp")
add_library(validation_sqlite STATIC "${SQL_ROOT}/native/third_party/sqlite/sqlite3.c")
target_include_directories(validation_sqlite PUBLIC "${SQL_ROOT}/native/third_party/sqlite")
target_compile_definitions(validation_sqlite PRIVATE
    SQLITE_THREADSAFE=1 SQLITE_DEFAULT_MEMSTATUS=0 SQLITE_DQS=0 SQLITE_OMIT_LOAD_EXTENSION)

add_executable(sql_validation_test
    "${VALIDATION_ROOT}/qfli_sql_validation.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../qfli_sql_validation_test.cpp")
target_include_directories(sql_validation_test PRIVATE "${VALIDATION_ROOT}")
target_link_libraries(sql_validation_test PRIVATE validation_sqlite)
target_compile_options(sql_validation_test PRIVATE -Wall -Wextra -Werror)
target_link_options(sql_validation_test PRIVATE -Wl,--wrap=sqlite3_step)
if(UNIX)
    target_link_libraries(sql_validation_test PRIVATE pthread dl m)
endif()
add_test(NAME sql_validation_real_engine
    COMMAND sql_validation_test "${CMAKE_CURRENT_BINARY_DIR}")
