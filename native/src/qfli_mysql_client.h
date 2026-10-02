#ifndef QFLI_MYSQL_CLIENT_H
#define QFLI_MYSQL_CLIENT_H

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace qfli_mysql {

struct Column {
    std::string name;
    unsigned int native_type = 0;
    bool binary = false;
};

struct Cell {
    bool is_null = true;
    // Binary columns use uppercase hexadecimal; other values retain server text.
    std::string text;
};

struct QueryResult {
    bool available = false;
    unsigned int error_code = 0;
    std::string sql_state;
    std::string error;
    std::uint64_t affected_rows = 0;
    bool truncated = false;
    std::vector<Column> columns;
    std::vector<std::vector<Cell>> rows;
};

struct QueryLimits {
    std::size_t rows = 1000;
    std::size_t bytes = 1024 * 1024;
};

struct ScriptResult {
    QueryResult summary;
    std::vector<QueryResult> results;
};

QueryResult query(const std::string &socket_path, const std::string &schema,
                  const std::string &source,
                  const std::vector<std::optional<std::string>> &parameters = {},
                  QueryLimits limits = {});
QueryResult query(const std::string &socket_path, const std::string &schema,
                  const std::string &source,
                  const std::vector<std::optional<std::string>> &parameters,
                  QueryLimits limits, const std::string &password);

QueryResult shutdown(const std::string &socket_path);
QueryResult shutdown(const std::string &socket_path, const std::string &password);

ScriptResult execute_script(const std::string &socket_path, const std::string &schema,
                            const std::string &source, QueryLimits limits = {});
ScriptResult execute_script(const std::string &socket_path, const std::string &schema,
                            const std::string &source, QueryLimits limits,
                            const std::string &password);

const char *client_version();

}  // namespace qfli_mysql

#endif
