cmake_minimum_required(VERSION 3.18)
project(qfli_mysql_host_tests LANGUAGES CXX)

# Required so CTest discovers the lifecycle and bridge tests.
enable_testing()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(HOST_MYSQL REQUIRED IMPORTED_TARGET mysqlclient)
find_path(RAPIDJSON_INCLUDE_DIR rapidjson/document.h REQUIRED)

add_library(qfli_mysql_host_client STATIC ../src/qfli_mysql_client.cpp)
target_include_directories(qfli_mysql_host_client PUBLIC ../src)
target_link_libraries(qfli_mysql_host_client PUBLIC PkgConfig::HOST_MYSQL)
target_compile_options(qfli_mysql_host_client PRIVATE -Wall -Wextra -Werror)

add_executable(mysql_client_test mysql_client_test.cpp)
target_link_libraries(mysql_client_test PRIVATE qfli_mysql_host_client)

add_executable(mysql_query_bridge mysql_query_bridge.cpp)
target_include_directories(mysql_query_bridge SYSTEM PRIVATE ${RAPIDJSON_INCLUDE_DIR})
target_link_libraries(mysql_query_bridge PRIVATE qfli_mysql_host_client)

foreach(test_target mysql_client_test mysql_query_bridge)
  target_compile_options(${test_target} PRIVATE -Wall -Wextra -Werror)
endforeach()

# Phone host lifecycle: exercises the real production host and launcher. The
# stub server library is staged beside the launcher so its dladdr-derived
# directory resolves to the staged server entry.
add_library(qfli_mysql_host_core STATIC ../mysql/qfli_mysql_host.cpp)
target_include_directories(qfli_mysql_host_core PUBLIC ../mysql)
target_compile_options(qfli_mysql_host_core PRIVATE -Wall -Wextra -Werror)
target_link_options(qfli_mysql_host_core PUBLIC -ldl)

add_library(qfli_mysql_server_stub SHARED qfli_mysql_child_stub.cpp)
set_target_properties(qfli_mysql_server_stub PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
  OUTPUT_NAME qfli_mysql_server)
target_compile_options(qfli_mysql_server_stub PRIVATE -Wall -Wextra -Werror)

add_executable(qfli_mysql_launcher_pie ../mysql/qfli_mysql_launcher.cpp)
target_compile_options(qfli_mysql_launcher_pie PRIVATE -Wall -Wextra -Werror)
target_link_libraries(qfli_mysql_launcher_pie PRIVATE pthread)
target_link_options(qfli_mysql_launcher_pie PRIVATE -Wl,-rpath,$ORIGIN)
set_target_properties(qfli_mysql_launcher_pie PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
  OUTPUT_NAME qfli_mysql_launcher)

add_executable(qfli_mysql_host_test qfli_mysql_host_test.cpp)
target_link_libraries(qfli_mysql_host_test PRIVATE qfli_mysql_host_core)
target_compile_options(qfli_mysql_host_test PRIVATE -Wall -Wextra -Werror)
# The launcher and stub server must exist before the test runs.
add_dependencies(qfli_mysql_host_test qfli_mysql_launcher_pie qfli_mysql_server_stub)
add_test(NAME qfli_mysql_host_test
  COMMAND qfli_mysql_host_test $<TARGET_FILE:qfli_mysql_launcher_pie>)

add_library(qfli_mysql_preload_host_stub SHARED qfli_mysql_preload_host_stub.cpp)
target_compile_options(qfli_mysql_preload_host_stub PRIVATE -Wall -Wextra -Werror)
add_executable(qfli_mysql_preload_host_test
  qfli_mysql_preload_host_test.cpp
  ../../ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp)
target_include_directories(qfli_mysql_preload_host_test PRIVATE
  ../../ohos/entry/src/main/cpp)
target_link_libraries(qfli_mysql_preload_host_test PRIVATE qfli_mysql_host_core dl pthread)
target_compile_options(qfli_mysql_preload_host_test PRIVATE -Wall -Wextra -Werror)
target_link_options(qfli_mysql_preload_host_test PRIVATE -Wl,--wrap=pthread_create)
add_dependencies(qfli_mysql_preload_host_test qfli_mysql_preload_host_stub)
add_test(NAME qfli_mysql_preload_host_test
  COMMAND qfli_mysql_preload_host_test $<TARGET_FILE:qfli_mysql_preload_host_stub>)
set_tests_properties(qfli_mysql_preload_host_test PROPERTIES TIMEOUT 20)
