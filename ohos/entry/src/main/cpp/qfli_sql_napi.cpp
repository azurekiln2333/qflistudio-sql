#include "napi/native_api.h"

#include <cctype>
#include <string>

#include "qfli_sql_bridge.h"
#include "sqlite3.h"

namespace {

bool read_string(napi_env env, napi_value value, std::string *out)
{
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok || type != napi_string) {
        return false;
    }
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    std::string buffer(length + 1, '\0');
    if (length > 0 && napi_get_value_string_utf8(
            env, value, &buffer[0], length + 1, &length) != napi_ok) {
        return false;
    }
    buffer.resize(length);
    *out = buffer;
    return true;
}

napi_value make_string(napi_env env, const char *value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value == nullptr ? "" : value, NAPI_AUTO_LENGTH, &result);
    return result;
}

void set_string(napi_env env, napi_value object, const char *name, const char *value)
{
    napi_set_named_property(env, object, name, make_string(env, value));
}

void set_number(napi_env env, napi_value object, const char *name, int value)
{
    napi_value item = nullptr;
    napi_create_int32(env, value, &item);
    napi_set_named_property(env, object, name, item);
}

void set_boolean(napi_env env, napi_value object, const char *name, bool value)
{
    napi_value item = nullptr;
    napi_get_boolean(env, value, &item);
    napi_set_named_property(env, object, name, item);
}

napi_value query(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3] = {nullptr, nullptr, nullptr};
    napi_value this_arg = nullptr;
    std::string source;
    std::string database_path;
    bool is_array = false;
    if (napi_get_cb_info(env, info, &argc, argv, &this_arg, nullptr) != napi_ok ||
        argc < 3 || !read_string(env, argv[0], &source) ||
        !read_string(env, argv[1], &database_path) ||
        napi_is_array(env, argv[2], &is_array) != napi_ok || !is_array) {
        napi_throw_type_error(env, nullptr, "query(source, databasePath, params) expects two strings and an array");
        return nullptr;
    }

    napi_value columns = nullptr;
    napi_value rows = nullptr;
    napi_create_array(env, &columns);
    napi_create_array(env, &rows);
    std::string error;
    sqlite3 *database = nullptr;
    sqlite3_stmt *statement = nullptr;
    int affected_rows = 0;
    bool truncated = false;
    bool available = true;

    do {
        const int opened = sqlite3_open_v2(database_path.c_str(), &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr);
        if (opened != SQLITE_OK) {
            error = database == nullptr ? "SQLite database open failed." : sqlite3_errmsg(database);
            break;
        }
        sqlite3_busy_timeout(database, 3000);
        const char *tail = nullptr;
        if (sqlite3_prepare_v2(database, source.c_str(), -1, &statement, &tail) != SQLITE_OK) {
            error = sqlite3_errmsg(database);
            break;
        }
        while (tail != nullptr && *tail != '\0') {
            if (!std::isspace(static_cast<unsigned char>(*tail))) {
                error = "Only one SQL statement is allowed in a grid query.";
                break;
            }
            ++tail;
        }
        if (!error.empty() || statement == nullptr) break;

        uint32_t parameter_count = 0;
        napi_get_array_length(env, argv[2], &parameter_count);
        if (parameter_count != static_cast<uint32_t>(sqlite3_bind_parameter_count(statement))) {
            error = "SQL parameter count does not match the supplied values.";
            break;
        }
        for (uint32_t index = 0; index < parameter_count; ++index) {
            napi_value item = nullptr;
            napi_valuetype type = napi_undefined;
            napi_get_element(env, argv[2], index, &item);
            napi_typeof(env, item, &type);
            if (type == napi_null) {
                sqlite3_bind_null(statement, static_cast<int>(index + 1));
            } else {
                std::string value;
                if (!read_string(env, item, &value)) {
                    error = "SQL parameters must be strings or null.";
                    break;
                }
                sqlite3_bind_text(statement, static_cast<int>(index + 1),
                    value.c_str(), static_cast<int>(value.size()), SQLITE_TRANSIENT);
            }
        }
        if (!error.empty()) break;

        const int column_count = sqlite3_column_count(statement);
        for (int index = 0; index < column_count; ++index) {
            napi_set_element(env, columns, index,
                make_string(env, sqlite3_column_name(statement, index)));
        }
        uint32_t row_index = 0;
        size_t output_bytes = 0;
        for (;;) {
            const int code = sqlite3_step(statement);
            if (code == SQLITE_DONE) {
                affected_rows = sqlite3_changes(database);
                break;
            }
            if (code != SQLITE_ROW) {
                error = sqlite3_errmsg(database);
                break;
            }
            if (row_index >= 500) {
                truncated = true;
                break;
            }
            napi_value row = nullptr;
            napi_create_array_with_length(env, column_count, &row);
            for (int index = 0; index < column_count; ++index) {
                napi_value cell = nullptr;
                if (sqlite3_column_type(statement, index) == SQLITE_NULL) {
                    napi_get_null(env, &cell);
                } else {
                    const char *value = reinterpret_cast<const char *>(
                        sqlite3_column_text(statement, index));
                    const int length = sqlite3_column_bytes(statement, index);
                    if (value == nullptr || length < 0 ||
                        output_bytes + static_cast<size_t>(length) > 1024 * 1024) {
                        truncated = true;
                        break;
                    }
                    output_bytes += static_cast<size_t>(length);
                    napi_create_string_utf8(env, value, static_cast<size_t>(length), &cell);
                }
                napi_set_element(env, row, index, cell);
            }
            if (truncated) break;
            napi_set_element(env, rows, row_index++, row);
        }
    } while (false);

    if (statement != nullptr) sqlite3_finalize(statement);
    if (database != nullptr) sqlite3_close(database);

    napi_value result = nullptr;
    napi_create_object(env, &result);
    set_boolean(env, result, "available", available);
    set_number(env, result, "exitCode", error.empty() ? 0 : 1);
    set_string(env, result, "error", error.c_str());
    set_number(env, result, "affectedRows", affected_rows);
    set_boolean(env, result, "truncated", truncated);
    napi_set_named_property(env, result, "columns", columns);
    napi_set_named_property(env, result, "rows", rows);
    return result;
}

napi_value execute(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_value this_arg = nullptr;
    std::string source;
    std::string database_path;
    QfliSqlResult raw;
    napi_value result = nullptr;
    napi_value value = nullptr;

    if (napi_get_cb_info(env, info, &argc, argv, &this_arg, nullptr) != napi_ok ||
        argc < 2 || !read_string(env, argv[0], &source) ||
        !read_string(env, argv[1], &database_path)) {
        napi_throw_type_error(env, nullptr, "execute(source, databasePath) expects two strings");
        return nullptr;
    }
    if (!qfli_sql_execute(source.c_str(), database_path.c_str(), 1024 * 1024, &raw)) {
        napi_throw_error(env, nullptr, "SQLite bridge could not create a result");
        return nullptr;
    }

    napi_create_object(env, &result);
    napi_get_boolean(env, raw.available != 0, &value);
    napi_set_named_property(env, result, "available", value);
    napi_create_int32(env, raw.exit_code, &value);
    napi_set_named_property(env, result, "exitCode", value);
    napi_set_named_property(env, result, "output", make_string(env, raw.output));
    napi_set_named_property(env, result, "error", make_string(env, raw.error));
    napi_get_boolean(env, raw.truncated != 0, &value);
    napi_set_named_property(env, result, "truncated", value);
    qfli_sql_result_free(&raw);
    return result;
}

napi_value version(napi_env env, napi_callback_info info)
{
    (void)info;
    return make_string(env, qfli_sql_version());
}

napi_value init(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        {"execute", nullptr, execute, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"query", nullptr, query, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"version", nullptr, version, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, 3, properties);
    return exports;
}

} // namespace

static napi_module qfli_sql_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = init,
    .nm_modname = "qfli_sql",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void register_qfli_sql_module()
{
    napi_module_register(&qfli_sql_module);
}
