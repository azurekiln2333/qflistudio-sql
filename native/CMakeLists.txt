cmake_minimum_required(VERSION 3.5.0)
project(qfli_sql C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_CXX_STANDARD 17)

set(QFLI_SQL_DIR ${CMAKE_CURRENT_SOURCE_DIR})
set(QFLI_SQLITE_DIR ${QFLI_SQL_DIR}/third_party/sqlite)

add_library(qfli_sql SHARED
    ${QFLI_SQLITE_DIR}/sqlite3.c
    src/qfli_sql_bridge.c
    ../ohos/entry/src/main/cpp/qfli_sql_validation.cpp
    ../ohos/entry/src/main/cpp/qfli_sql_napi.cpp)

target_include_directories(qfli_sql PRIVATE
    ${QFLI_SQLITE_DIR}
    ${QFLI_SQL_DIR}/src
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/include)

target_compile_definitions(qfli_sql PRIVATE
    SQLITE_THREADSAFE=1
    SQLITE_DEFAULT_MEMSTATUS=0
    SQLITE_DQS=0
    SQLITE_OMIT_LOAD_EXTENSION)

target_compile_options(qfli_sql PRIVATE
    -Wall
    -Wextra
    -Wno-unused-parameter
    -Wno-error=format-security)

target_link_libraries(qfli_sql PUBLIC
    -static-libstdc++
    libace_napi.z.so
    libhilog_ndk.z.so
    m)

if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$" OR OHOS_ARCH STREQUAL "arm64-v8a")
    set(QFLI_MYSQL_ABI arm64-v8a)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$" OR OHOS_ARCH STREQUAL "x86_64")
    set(QFLI_MYSQL_ABI x86_64)
endif()

if(QFLI_MYSQL_ABI)
    set(QFLI_MYSQL_RUNTIME "${QFLI_SQL_DIR}/../build/mysql-port/package/libs/${QFLI_MYSQL_ABI}")
    if(NOT EXISTS "${QFLI_SQL_DIR}/../build/mysql-port/package/rawfile/mysql/runtime.json")
        message(FATAL_ERROR "Oracle MySQL runtime resources are missing; build native/mysql first")
    endif()
    foreach(library qfli_mysql qfli_mysql_server qfli_mysql_launcher qfli_mysql_server_proto)
        if(NOT EXISTS "${QFLI_MYSQL_RUNTIME}/lib${library}.so")
            message(FATAL_ERROR
                "Real Oracle MySQL ${QFLI_MYSQL_ABI} runtime is missing: ${QFLI_MYSQL_RUNTIME}/lib${library}.so")
        endif()
    endforeach()
else()
    add_library(qfli_mysql SHARED
        src/qfli_mysql_unavailable.cpp
        ${QFLI_SQL_DIR}/mysql/qfli_mysql_host.cpp
        ../ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp
        ../ohos/entry/src/main/cpp/qfli_mysql_napi.cpp)
    target_include_directories(qfli_mysql PRIVATE
        ${QFLI_SQL_DIR}/src ${QFLI_SQL_DIR}/mysql
        ../ohos/entry/src/main/cpp)
    target_link_libraries(qfli_mysql PRIVATE -static-libstdc++ libace_napi.z.so dl)
endif()
