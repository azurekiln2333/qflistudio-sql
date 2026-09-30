if(NOT CMAKE_CROSSCOMPILING OR NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
  message(FATAL_ERROR "The MySQL child runtime requires the HarmonyOS arm64 toolchain")
endif()

get_filename_component(QFLI_MYSQL_REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(QFLI_MYSQL_RUNTIME_LIBDIR "${CMAKE_BINARY_DIR}/qfli-runtime/lib")

# Reuse Oracle's complete server link graph, including static storage engines.
get_target_property(QFLI_MYSQL_SERVER_LIBRARIES mysqld LINK_LIBRARIES)
add_library(qfli_mysql_server SHARED "${CMAKE_CURRENT_LIST_DIR}/qfli_mysql_server.cpp")
target_link_libraries(qfli_mysql_server PRIVATE ${QFLI_MYSQL_SERVER_LIBRARIES} extra::rapidjson)
target_link_options(qfli_mysql_server PRIVATE "LINKER:--no-undefined")
set_target_properties(qfli_mysql_server PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY "${QFLI_MYSQL_RUNTIME_LIBDIR}")

find_library(QFLI_MYSQL_NAPI_LIBRARY NAMES ace_napi.z REQUIRED)
add_library(qfli_mysql SHARED
  "${QFLI_MYSQL_REPO_ROOT}/native/src/qfli_mysql_client.cpp"
  "${QFLI_MYSQL_REPO_ROOT}/ohos/entry/src/main/cpp/qfli_mysql_napi.cpp")
target_include_directories(qfli_mysql PRIVATE
  "${QFLI_MYSQL_REPO_ROOT}/native/src"
  "${CMAKE_SOURCE_DIR}/include"
  "${CMAKE_BINARY_DIR}/include")
target_link_libraries(qfli_mysql PRIVATE mysqlclient ${QFLI_MYSQL_NAPI_LIBRARY})
target_link_options(qfli_mysql PRIVATE "LINKER:--no-undefined")
set_target_properties(qfli_mysql PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY "${QFLI_MYSQL_RUNTIME_LIBDIR}")
