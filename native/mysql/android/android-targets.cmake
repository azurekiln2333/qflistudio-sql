if(NOT CMAKE_CROSSCOMPILING OR NOT QFLI_ANDROID_NDK)
  message(FATAL_ERROR "This runtime requires the Android NDK toolchain")
endif()
get_filename_component(QFLI_MYSQL_REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
target_link_libraries(mysqld log)
add_library(qfli_mysql_bridge SHARED
  "${QFLI_MYSQL_REPO_ROOT}/native/src/qfli_mysql_client.cpp"
  "${QFLI_MYSQL_REPO_ROOT}/native/src/qfli_mysql_ffi.cpp")
target_include_directories(qfli_mysql_bridge PRIVATE
  "${QFLI_MYSQL_REPO_ROOT}/native/src" "${CMAKE_SOURCE_DIR}/include" "${CMAKE_BINARY_DIR}/include")
target_include_directories(qfli_mysql_bridge SYSTEM PRIVATE "${CMAKE_SOURCE_DIR}/extra/rapidjson/include")
target_link_libraries(qfli_mysql_bridge PRIVATE mysqlclient)
target_compile_features(qfli_mysql_bridge PRIVATE cxx_std_17)
target_link_options(qfli_mysql_bridge PRIVATE "LINKER:--no-undefined")
add_executable(qfli_mysql_launcher "${CMAKE_CURRENT_LIST_DIR}/../desktop/launcher.cpp")
target_compile_features(qfli_mysql_launcher PRIVATE cxx_std_17)
set_target_properties(qfli_mysql_bridge qfli_mysql_launcher PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qfli-runtime/lib"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qfli-runtime/bin")
