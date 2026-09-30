#include "qfli_mysql_client.h"

#include <mysql.h>

#include <algorithm>
#include <memory>
#include <mutex>

namespace qfli_mysql {
namespace {

std::once_flag library_once;
int library_error = 1;

struct ThreadContext {
    bool initialized = mysql_thread_init() == 0;
    ~ThreadContext() { if (initialized) mysql_thread_end(); }
};

struct ConnectionCloser {
    void operator()(MYSQL *connection) const { mysql_close(connection); }
};

struct StatementCloser {
    void operator()(MYSQL_STMT *statement) const { mysql_stmt_close(statement); }
};

struct ResultCloser {
    void operator()(MYSQL_RES *result) const { mysql_free_result(result); }
};

void set_error(QueryResult &result, MYSQL *connection)
{
    result.error_code = mysql_errno(connection);
    result.sql_state = mysql_sqlstate(connection);
    result.error = mysql_error(connection);
}

void set_error(QueryResult &result, MYSQL_STMT *statement)
{
    result.error_code = mysql_stmt_errno(statement);
    result.sql_state = mysql_stmt_sqlstate(statement);
    result.error = mysql_stmt_error(statement);
}

void local_error(QueryResult &result, const char *message)
{
    result.error_code = 1;
    result.error = message;
}

bool is_binary(const MYSQL_FIELD &field)
{
    if (field.charsetnr != 63) return false;
    switch (field.type) {
    case MYSQL_TYPE_STRING:
    case MYSQL_TYPE_VAR_STRING:
    case MYSQL_TYPE_VARCHAR:
    case MYSQL_TYPE_TINY_BLOB:
    case MYSQL_TYPE_MEDIUM_BLOB:
    case MYSQL_TYPE_LONG_BLOB:
    case MYSQL_TYPE_BLOB:
    case MYSQL_TYPE_BIT:
    case MYSQL_TYPE_GEOMETRY:
        return true;
    default:
        return false;
    }
}

std::string hexadecimal(const char *bytes, std::size_t length)
{
    constexpr char digits[] = "0123456789ABCDEF";
    std::string value(length * 2, '\0');
    for (std::size_t index = 0; index < length; ++index) {
        const auto byte = static_cast<unsigned char>(bytes[index]);
        value[index * 2] = digits[byte >> 4];
        value[index * 2 + 1] = digits[byte & 15];
    }
    return value;
}

}  // namespace

QueryResult query(const std::string &socket_path, const std::string &schema,
                  const std::string &source,
                  const std::vector<std::optional<std::string>> &parameters,
                  QueryLimits limits)
{
    QueryResult result;
    if (socket_path.empty() || socket_path.find('\0') != std::string::npos ||
        schema.find('\0') != std::string::npos) {
        local_error(result, "Invalid local MySQL connection path or schema.");
        return result;
    }
    if (source.size() > 1024 * 1024 || limits.bytes == 0 || limits.rows == 0) {
        local_error(result, "SQL input or result limits are invalid.");
        return result;
    }
    std::size_t parameter_bytes = 0;
    for (const auto &parameter : parameters) {
        if (!parameter) continue;
        if (parameter->size() > 1024 * 1024 - parameter_bytes) {
            local_error(result, "Bound SQL values exceed the input limit.");
            return result;
        }
        parameter_bytes += parameter->size();
    }
    std::call_once(library_once, [] { library_error = mysql_library_init(0, nullptr, nullptr); });
    if (library_error != 0) {
        local_error(result, "Could not initialize the Oracle MySQL client.");
        return result;
    }
    ThreadContext thread;
    if (!thread.initialized) {
        local_error(result, "Could not initialize the MySQL client thread.");
        return result;
    }
    std::unique_ptr<MYSQL, ConnectionCloser> connection(mysql_init(nullptr));
    if (!connection) {
        local_error(result, "Could not allocate a MySQL connection.");
        return result;
    }
    const unsigned int timeout = 5;
    const auto protocol = MYSQL_PROTOCOL_SOCKET;
    const auto ssl_mode = SSL_MODE_DISABLED;
    const unsigned long max_packet = 8 * 1024 * 1024;
    if (mysql_options(connection.get(), MYSQL_OPT_PROTOCOL, &protocol) != 0 ||
        mysql_options(connection.get(), MYSQL_OPT_CONNECT_TIMEOUT, &timeout) != 0 ||
        mysql_options(connection.get(), MYSQL_OPT_READ_TIMEOUT, &timeout) != 0 ||
        mysql_options(connection.get(), MYSQL_OPT_WRITE_TIMEOUT, &timeout) != 0 ||
        mysql_options(connection.get(), MYSQL_OPT_SSL_MODE, &ssl_mode) != 0 ||
        mysql_options(connection.get(), MYSQL_OPT_MAX_ALLOWED_PACKET, &max_packet) != 0) {
        set_error(result, connection.get());
        return result;
    }
    if (!mysql_real_connect(connection.get(), "localhost", "root", "",
                            schema.empty() ? nullptr : schema.c_str(), 0,
                            socket_path.c_str(), CLIENT_FOUND_ROWS)) {
        set_error(result, connection.get());
        return result;
    }
    result.available = true;
    if (mysql_set_character_set(connection.get(), "utf8mb4") != 0) {
        set_error(result, connection.get());
        return result;
    }
    std::unique_ptr<MYSQL_STMT, StatementCloser> statement(mysql_stmt_init(connection.get()));
    if (!statement) {
        set_error(result, connection.get());
        return result;
    }
    if (mysql_stmt_prepare(statement.get(), source.data(), source.size()) != 0) {
        set_error(result, statement.get());
        return result;
    }
    if (mysql_stmt_param_count(statement.get()) != parameters.size()) {
        local_error(result, "SQL parameter count does not match the bound values.");
        return result;
    }
    std::vector<MYSQL_BIND> inputs(parameters.size());
    for (std::size_t index = 0; index < parameters.size(); ++index) {
        auto &input = inputs[index];
        const auto &parameter = parameters[index];
        input.buffer_type = parameter ? MYSQL_TYPE_STRING : MYSQL_TYPE_NULL;
        if (parameter) {
            input.buffer = const_cast<char *>(parameter->data());
            input.buffer_length = parameter->size();
        }
    }
    if ((!inputs.empty() && mysql_stmt_bind_param(statement.get(), inputs.data()) != 0) ||
        mysql_stmt_execute(statement.get()) != 0) {
        set_error(result, statement.get());
        return result;
    }
    std::unique_ptr<MYSQL_RES, ResultCloser> metadata(mysql_stmt_result_metadata(statement.get()));
    if (!metadata) {
        if (mysql_stmt_field_count(statement.get()) != 0) {
            set_error(result, statement.get());
        } else {
            result.affected_rows = mysql_stmt_affected_rows(statement.get());
        }
        return result;
    }

    const auto count = mysql_num_fields(metadata.get());
    auto *fields = mysql_fetch_fields(metadata.get());
    std::size_t used_bytes = 0;
    for (unsigned int index = 0; index < count; ++index) {
        const auto &field = fields[index];
        result.columns.push_back({std::string(field.name, field.name_length),
                                  static_cast<unsigned int>(field.type), is_binary(field)});
        used_bytes += sizeof(Column) + field.name_length;
    }
    if (used_bytes > limits.bytes) {
        result.truncated = true;
        return result;
    }
    std::vector<MYSQL_BIND> outputs(count);
    std::vector<std::vector<char>> buffers(count, std::vector<char>(256));
    std::vector<unsigned long> lengths(count, 0);
    auto nulls = std::make_unique<bool[]>(count);
    for (unsigned int index = 0; index < count; ++index) {
        auto &output = outputs[index];
        output.buffer_type = MYSQL_TYPE_STRING;
        output.buffer = buffers[index].data();
        output.buffer_length = buffers[index].size();
        output.length = &lengths[index];
        output.is_null = &nulls[index];
    }
    if (mysql_stmt_bind_result(statement.get(), outputs.data()) != 0) {
        set_error(result, statement.get());
        return result;
    }
    for (;;) {
        const int status = mysql_stmt_fetch(statement.get());
        if (status == MYSQL_NO_DATA) return result;
        if (status != 0 && status != MYSQL_DATA_TRUNCATED) {
            set_error(result, statement.get());
            return result;
        }
        if (result.rows.size() >= limits.rows) {
            result.truncated = true;
            return result;
        }
        std::size_t row_bytes = count * sizeof(Cell);
        if (row_bytes > limits.bytes - used_bytes) {
            result.truncated = true;
            return result;
        }
        for (unsigned int index = 0; index < count; ++index) {
            if (nulls[index]) continue;
            const std::size_t factor = result.columns[index].binary ? 2 : 1;
            if (lengths[index] > (limits.bytes - used_bytes - row_bytes) / factor) {
                result.truncated = true;
                return result;
            }
            row_bytes += lengths[index] * factor;
        }
        std::vector<Cell> row;
        row.reserve(count);
        for (unsigned int index = 0; index < count; ++index) {
            Cell cell;
            cell.is_null = nulls[index];
            if (!cell.is_null) {
                std::vector<char> full;
                const char *bytes = buffers[index].data();
                if (lengths[index] > buffers[index].size()) {
                    full.resize(lengths[index]);
                    MYSQL_BIND fetch{};
                    fetch.buffer_type = MYSQL_TYPE_STRING;
                    fetch.buffer = full.data();
                    fetch.buffer_length = full.size();
                    if (mysql_stmt_fetch_column(statement.get(), &fetch, index, 0) != 0) {
                        set_error(result, statement.get());
                        return result;
                    }
                    bytes = full.data();
                }
                cell.text = result.columns[index].binary
                    ? hexadecimal(bytes, lengths[index])
                    : std::string(bytes, lengths[index]);
            }
            row.push_back(std::move(cell));
        }
        used_bytes += row_bytes;
        result.rows.push_back(std::move(row));
    }
}

}  // namespace qfli_mysql
