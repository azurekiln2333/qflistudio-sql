cmake_minimum_required(VERSION 3.18)
project(qfli_mysql_host_tests LANGUAGES CXX)

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
