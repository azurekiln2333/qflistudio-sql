#include "napi/native_api.h"

#include <cctype>
#include <exception>
#include <memory>
#include <string>

#include "qfli_sql_bridge.h"
#include "qfli_sql_validation.h"
#include "sqlite3.h"

namespace {

constexpr uint32_t kMaxScriptStatements = 512;
constexpr int kMaxScriptRows = 500;
constexpr long long kMaxScriptBytes = 1024LL * 1024LL;

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

napi_value empty_array(napi_env env)
{
    napi_value array = nullptr;
    napi_create_array(env, &array);
    return array;
}

/// Builds the shared structured result shape used by query and every script item.
napi_value make_result(napi_env env, int exit_code, const std::string &error,
    int affected_rows, bool truncated, napi_value columns, napi_value rows)
{
    napi_value result = nullptr;
    napi_create_object(env, &result);
    set_boolean(env, result, "available", true);
    set_number(env, result, "exitCode", exit_code);
    set_string(env, result, "error", error.c_str());
    set_number(env, result, "affectedRows", affected_rows);
    set_boolean(env, result, "truncated", truncated);
    napi_set_named_property(env, result, "columns", columns);
    napi_set_named_property(env, result, "rows", rows);
    return result;
}

bool has_sql_content(const char *source)
{
    if (source == nullptr) return false;
    for (const char *cursor = source; *cursor != '\0'; ++cursor) {
        if (!std::isspace(static_cast<unsigned char>(*cursor))) return true;
    }
    return false;
}

/// Remaining display budget shared by every statement in one script.
struct ScriptBudget {
    int rows = 0;
    long long bytes = 0;
};

/// One statement executed on the caller's connection.
struct StatementOutcome {
    napi_value columns = nullptr;
    napi_value rows = nullptr;
    int affected_rows = 0;
    bool truncated = false;
    bool has_statement = false;
    std::string error;
    const char *tail = nullptr;
};

/// Uses SQLite prepare/tail boundaries so string literals, transactions and
/// triggers are never split on ';'.
StatementOutcome run_script_statement(napi_env env, sqlite3 *database,
    const char *source, ScriptBudget *budget, bool allow_execution)
{
    StatementOutcome outcome;
    outcome.columns = empty_array(env);
    outcome.rows = empty_array(env);
    sqlite3_stmt *statement = nullptr;
    const char *tail = nullptr;
    const int prepared = sqlite3_prepare_v2(database, source, -1, &statement, &tail);
    outcome.tail = tail;
    if (prepared != SQLITE_OK) {
        outcome.error = sqlite3_errmsg(database);
        if (statement != nullptr) sqlite3_finalize(statement);
        return outcome;
    }
    outcome.has_statement = statement != nullptr;
    if (statement == nullptr) return outcome;
    // Only a real prepared statement consumes the cap. Comments and empty
    // separators after statement 512 are valid; statement 513 never steps.
    if (!allow_execution) {
        outcome.error = "SQL script exceeds the 512 statement limit.";
        sqlite3_finalize(statement);
        return outcome;
    }

    const int column_count = sqlite3_column_count(statement);
    for (int index = 0; index < column_count; ++index) {
        napi_set_element(env, outcome.columns, index,
            make_string(env, sqlite3_column_name(statement, index)));
    }
    uint32_t row_index = 0;
    for (;;) {
        const int code = sqlite3_step(statement);
        if (code == SQLITE_DONE) {
            outcome.affected_rows = column_count == 0 ? sqlite3_changes(database) : 0;
            break;
        }
        if (code != SQLITE_ROW) {
            outcome.error = sqlite3_errmsg(database);
            break;
        }
        if (budget->rows >= kMaxScriptRows) {
            outcome.truncated = true;
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
                    budget->bytes + length > kMaxScriptBytes) {
                    outcome.truncated = true;
                    break;
                }
                budget->bytes += length;
                napi_create_string_utf8(env, value, static_cast<size_t>(length), &cell);
            }
            napi_set_element(env, row, index, cell);
        }
        if (outcome.truncated) break;
        // The display budget is shared across the script, but array indices
        // belong to this result set. A shared index creates sparse/null rows in
        // the second SELECT and makes the structured Dart decoder reject it.
        napi_set_element(env, outcome.rows, row_index++, row);
        ++budget->rows;
    }
    sqlite3_finalize(statement);
    return outcome;
}

napi_value execute_script(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_value this_arg = nullptr;
    std::string source;
    std::string database_path;
    if (napi_get_cb_info(env, info, &argc, argv, &this_arg, nullptr) != napi_ok ||
        argc < 2 || !read_string(env, argv[0], &source) ||
        !read_string(env, argv[1], &database_path)) {
        napi_throw_type_error(env, nullptr,
            "executeScript(source, databasePath) expects two strings");
        return nullptr;
    }

    napi_value results = empty_array(env);
    if (source.find('\0') != std::string::npos ||
        database_path.find('\0') != std::string::npos) {
        napi_throw_error(env, nullptr,
            "SQL source and database path cannot contain NUL.");
        return nullptr;
    }

    sqlite3 *database = nullptr;
    const int opened = sqlite3_open_v2(database_path.c_str(), &database,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr);
    if (opened != SQLITE_OK) {
        const std::string error = database == nullptr
            ? "SQLite database open failed." : sqlite3_errmsg(database);
        if (database != nullptr) sqlite3_close(database);
        napi_value failure = make_result(env, 1, error, 0, false,
            empty_array(env), empty_array(env));
        napi_set_named_property(env, failure, "results", results);
        return failure;
    }
    sqlite3_busy_timeout(database, 3000);

    ScriptBudget budget;
    int summary_exit_code = 0;
    int summary_affected_rows = 0;
    bool summary_truncated = false;
    std::string summary_error;
    napi_value summary_columns = empty_array(env);
    napi_value summary_rows = empty_array(env);

    const char *remaining = source.c_str();
    while (has_sql_content(remaining)) {
        uint32_t completed = 0;
        napi_get_array_length(env, results, &completed);
        StatementOutcome outcome = run_script_statement(env, database, remaining,
            &budget, completed < kMaxScriptStatements);
        if (!outcome.has_statement && outcome.error.empty()) break;
        summary_exit_code = outcome.error.empty() ? 0 : 1;
        summary_error = outcome.error;
        summary_affected_rows = outcome.affected_rows;
        summary_truncated = outcome.truncated;
        summary_columns = outcome.columns;
        summary_rows = outcome.rows;
        if (outcome.has_statement && completed < kMaxScriptStatements) {
            napi_set_element(env, results, completed,
                make_result(env, summary_exit_code, outcome.error,
                    outcome.affected_rows, outcome.truncated,
                    outcome.columns, outcome.rows));
        }
        if (outcome.truncated) {
            summary_exit_code = 1;
            summary_error = "SQL script output exceeds the display limits.";
        }
        if (summary_exit_code != 0 || outcome.truncated ||
            outcome.tail == nullptr || outcome.tail <= remaining) {
            break;
        }
        remaining = outcome.tail;
    }
    sqlite3_close(database);

    napi_value response = make_result(env, summary_exit_code, summary_error,
        summary_affected_rows, summary_truncated, summary_columns, summary_rows);
    napi_set_named_property(env, response, "results", results);
    return response;
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

napi_value make_validation_result(napi_env env, const qfli_sql::ValidationResult &raw)
{
    napi_value result = nullptr;
    napi_create_object(env, &result);
    set_boolean(env, result, "available", raw.available);
    set_string(env, result, "engine", "sqlite");
    set_string(env, result, "version", raw.version.c_str());
    set_number(env, result, "statements", raw.statements);
    set_number(env, result, "checked", raw.checked);
    set_number(env, result, "schemaGaps", raw.schema_gaps);
    set_boolean(env, result, "truncated", raw.truncated);
    set_string(env, result, "error", raw.error.c_str());
    napi_value issues = empty_array(env);
    for (uint32_t index = 0; index < raw.issues.size(); ++index) {
        const qfli_sql::ValidationIssue &issue = raw.issues[index];
        napi_value item = nullptr;
        napi_create_object(env, &item);
        set_number(env, item, "startOffset", issue.start_offset);
        set_number(env, item, "endOffset", issue.end_offset);
        set_string(env, item, "message", issue.message.c_str());
        set_string(env, item, "code", issue.code.c_str());
        set_string(env, item, "severity", issue.severity.c_str());
        napi_set_element(env, issues, index, item);
    }
    napi_set_named_property(env, result, "issues", issues);
    napi_value skipped = empty_array(env);
    for (uint32_t index = 0; index < raw.skipped.size(); ++index) {
        const qfli_sql::ValidationSkipped &range = raw.skipped[index];
        napi_value item = nullptr;
        napi_create_object(env, &item);
        set_number(env, item, "startOffset", range.start_offset);
        set_number(env, item, "endOffset", range.end_offset);
        set_string(env, item, "keyword", range.keyword.c_str());
        set_string(env, item, "reason", range.reason.c_str());
        napi_set_element(env, skipped, index, item);
    }
    napi_set_named_property(env, result, "skipped", skipped);
    return result;
}

struct ValidationWork {
    std::string source;
    qfli_sql::ValidationResult result;
    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
};

void validate_on_worker(napi_env, void *data)
{
    ValidationWork *work = static_cast<ValidationWork *>(data);
    try {
        work->result = qfli_sql::validate_sql(work->source);
    } catch (const std::exception &error) {
        work->result.available = false;
        work->result.error = std::string("SQLite syntax validation failed: ") + error.what();
    } catch (...) {
        work->result.available = false;
        work->result.error = "SQLite syntax validation failed unexpectedly.";
    }
}

void validation_complete(napi_env env, napi_status status, void *data)
{
    std::unique_ptr<ValidationWork> work(static_cast<ValidationWork *>(data));
    if (status != napi_ok) {
        work->result.available = false;
        work->result.error = "SQLite syntax validation worker was cancelled.";
    }
    napi_resolve_deferred(env, work->deferred, make_validation_result(env, work->result));
    napi_delete_async_work(env, work->work);
}

napi_value validate(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_value this_arg = nullptr;
    napi_valuetype type = napi_undefined;
    size_t length = 0;
    if (napi_get_cb_info(env, info, &argc, argv, &this_arg, nullptr) != napi_ok ||
        argc != 1 || napi_typeof(env, argv[0], &type) != napi_ok || type != napi_string ||
        napi_get_value_string_utf8(env, argv[0], nullptr, 0, &length) != napi_ok) {
        napi_throw_type_error(env, nullptr, "validate(source) expects only a SQL string; no database path is accepted");
        return nullptr;
    }
    std::unique_ptr<ValidationWork> work(new ValidationWork());
    napi_value promise = nullptr;
    if (napi_create_promise(env, &work->deferred, &promise) != napi_ok) return nullptr;
    if (length > qfli_sql::kValidationMaxBytes) {
        work->result.version = sqlite3_libversion();
        work->result.truncated = true;
        work->result.error = "SQLite syntax validation exceeds the 1 MiB source limit.";
        napi_resolve_deferred(env, work->deferred, make_validation_result(env, work->result));
        return promise;
    }
    if (!read_string(env, argv[0], &work->source)) {
        work->result.error = "SQLite syntax validation could not read the source string.";
        napi_resolve_deferred(env, work->deferred, make_validation_result(env, work->result));
        return promise;
    }
    napi_value name = make_string(env, "qfliSqlValidate");
    if (napi_create_async_work(env, nullptr, name, validate_on_worker,
            validation_complete, work.get(), &work->work) != napi_ok ||
        napi_queue_async_work(env, work->work) != napi_ok) {
        if (work->work != nullptr) napi_delete_async_work(env, work->work);
        work->result.error = "SQLite syntax validation worker could not be scheduled.";
        napi_resolve_deferred(env, work->deferred, make_validation_result(env, work->result));
        return promise;
    }
    work.release();
    return promise;
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
        {"executeScript", nullptr, execute_script, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"query", nullptr, query, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"validate", nullptr, validate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"version", nullptr, version, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
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
