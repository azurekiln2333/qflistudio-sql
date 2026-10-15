if(NOT CMAKE_CROSSCOMPILING OR NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
  message(FATAL_ERROR "The MySQL child runtime requires the HarmonyOS arm64 toolchain")
endif()

get_filename_component(QFLI_MYSQL_REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(QFLI_MYSQL_RUNTIME_LIBDIR "${CMAKE_BINARY_DIR}/qfli-runtime/lib")

# Reuse Oracle's complete server link graph, including static storage engines.
get_target_property(QFLI_MYSQL_SERVER_LIBRARIES mysqld LINK_LIBRARIES)
add_library(qfli_mysql_server SHARED "${CMAKE_CURRENT_LIST_DIR}/qfli_mysql_server.cpp")
target_link_libraries(qfli_mysql_server PRIVATE ${QFLI_MYSQL_SERVER_LIBRARIES} extra::rapidjson)
target_link_options(qfli_mysql_server PRIVATE
  "LINKER:--no-undefined"
  # The fork host dlopen()s this library and resolves the entry by name, so the
  # entries must survive hidden-visibility defaults and packaging strip.
  "LINKER:--export-dynamic-symbol=qfli_mysql_child_main"
  "LINKER:--export-dynamic-symbol=QfliMysqlMain"
  "LINKER:--export-dynamic-symbol=qfli_mysql_record_exit")
set_target_properties(qfli_mysql_server PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY "${QFLI_MYSQL_RUNTIME_LIBDIR}")

find_library(QFLI_MYSQL_NAPI_LIBRARY NAMES ace_napi.z REQUIRED)
set(QFLI_MYSQL_NAPI_SOURCES
  "${QFLI_MYSQL_REPO_ROOT}/native/src/qfli_mysql_client.cpp"
  "${CMAKE_CURRENT_LIST_DIR}/qfli_mysql_host.cpp"
  "${QFLI_MYSQL_REPO_ROOT}/ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp"
  "${QFLI_MYSQL_REPO_ROOT}/ohos/entry/src/main/cpp/qfli_mysql_napi.cpp")
add_library(qfli_mysql SHARED ${QFLI_MYSQL_NAPI_SOURCES})
target_include_directories(qfli_mysql PRIVATE
  "${QFLI_MYSQL_REPO_ROOT}/native/src"
  "${QFLI_MYSQL_REPO_ROOT}/ohos/entry/src/main/cpp"
  "${CMAKE_CURRENT_LIST_DIR}"
  "${CMAKE_SOURCE_DIR}/include"
  "${CMAKE_BINARY_DIR}/include")
target_link_libraries(qfli_mysql PRIVATE mysqlclient ${QFLI_MYSQL_NAPI_LIBRARY} dl)
target_link_options(qfli_mysql PRIVATE "LINKER:--no-undefined")

# Phone host: a packaged PIE launcher exec'd by the forked child. Built as an
# executable but named .so so it ships in the HAP native library directory.
add_executable(qfli_mysql_launcher "${CMAKE_CURRENT_LIST_DIR}/qfli_mysql_launcher.cpp")
target_link_libraries(qfli_mysql_launcher PRIVATE pthread)
target_link_options(qfli_mysql_launcher PRIVATE
  "LINKER:--no-undefined"
  "LINKER:-rpath,$ORIGIN")
set_target_properties(qfli_mysql_launcher PROPERTIES
  OUTPUT_NAME "qfli_mysql_launcher"
  SUFFIX ".so"
  PREFIX "lib"
  RUNTIME_OUTPUT_DIRECTORY "${QFLI_MYSQL_RUNTIME_LIBDIR}")
set_target_properties(qfli_mysql PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY "${QFLI_MYSQL_RUNTIME_LIBDIR}")

# Preloaded private server host: the production phone host. Direct launch exec
# is denied by the app sandbox (EACCES), so the server image is bound privately
# (version script + symbolic binding + static libc++) and started in a forked
# child by calling its entry directly.
add_library(qfli_mysql_server_proto SHARED
  "${CMAKE_CURRENT_LIST_DIR}/qfli_mysql_server_proto.cpp"
  "${CMAKE_CURRENT_LIST_DIR}/qfli_mysql_server.cpp")
target_link_libraries(qfli_mysql_server_proto PRIVATE
  ${QFLI_MYSQL_SERVER_LIBRARIES} extra::rapidjson)
target_link_options(qfli_mysql_server_proto PRIVATE
  "LINKER:--no-undefined"
  "LINKER:-Bsymbolic-functions"
  "LINKER:--version-script=${CMAKE_CURRENT_LIST_DIR}/qfli_mysql_server_proto.map"
  "-nostdlib++")
target_link_libraries(qfli_mysql_server_proto PRIVATE
  "${QFLI_OHOS_SDK}/llvm/lib/aarch64-linux-ohos/c++/libc++_static.a"
  "${QFLI_OHOS_SDK}/llvm/lib/aarch64-linux-ohos/libunwind.a")
set_target_properties(qfli_mysql_server_proto PROPERTIES
  OUTPUT_NAME "qfli_mysql_server_proto"
  LIBRARY_OUTPUT_DIRECTORY "${QFLI_MYSQL_RUNTIME_LIBDIR}")
