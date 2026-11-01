#include "napi/native_api.h"
#include "qfli_mysql_client.h"

#include <signal.h>

#include <cerrno>
#include <cstring>
#include <exception>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace {

struct QueryWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string socket;
    std::string schema;
    std::string source;
    std::vector<std::optional<std::string>> parameters;
    qfli_mysql::QueryResult result;
    qfli_mysql::ScriptResult script;
    bool stopping = false;
    bool executing_script = false;
};

bool read_string(napi_env env, napi_value value, std::string &out)
{
    std::size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok ||
        length > 1024 * 1024) return false;
    std::string buffer(length + 1, '\0');
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length) != napi_ok) {
        return false;
    }
    buffer.resize(length);
    out = std::move(buffer);
    return true;
}

napi_value make_string(napi_env env, const std::string &text)
{
    napi_value value = nullptr;
    napi_create_string_utf8(env, text.data(), text.size(), &value);
    return value;
}

void set_boolean(napi_env env, napi_value object, const char *key, bool value)
{
    napi_value item = nullptr;
    napi_get_boolean(env, value, &item);
    napi_set_named_property(env, object, key, item);
}

void set_number(napi_env env, napi_value object, const char *key, double value)
{
    napi_value item = nullptr;
    napi_create_double(env, value, &item);
    napi_set_named_property(env, object, key, item);
}

napi_value encode_result(napi_env env, const qfli_mysql::QueryResult &result)
{
    napi_value object = nullptr;
    napi_create_object(env, &object);
    set_boolean(env, object, "available", result.available);
    set_boolean(env, object, "truncated", result.truncated);
    set_number(env, object, "exitCode", result.error_code);
    set_number(env, object, "affectedRows", static_cast<double>(result.affected_rows));
    napi_set_named_property(env, object, "error", make_string(env, result.error));
    napi_set_named_property(env, object, "sqlState", make_string(env, result.sql_state));

    napi_value columns = nullptr;
    napi_value column_info = nullptr;
    napi_create_array_with_length(env, result.columns.size(), &columns);
    napi_create_array_with_length(env, result.columns.size(), &column_info);
    for (std::size_t index = 0; index < result.columns.size(); ++index) {
        const auto &column = result.columns[index];
        napi_set_element(env, columns, index, make_string(env, column.name));
        napi_value metadata = nullptr;
        napi_create_object(env, &metadata);
        napi_set_named_property(env, metadata, "name", make_string(env, column.name));
        set_number(env, metadata, "nativeType", column.native_type);
        set_boolean(env, metadata, "binary", column.binary);
        napi_set_element(env, column_info, index, metadata);
    }
    napi_set_named_property(env, object, "columns", columns);
    napi_set_named_property(env, object, "columnInfo", column_info);

    napi_value rows = nullptr;
    napi_create_array_with_length(env, result.rows.size(), &rows);
    for (std::size_t index = 0; index < result.rows.size(); ++index) {
        const auto &row = result.rows[index];
        napi_value cells = nullptr;
        napi_create_array_with_length(env, row.size(), &cells);
        for (std::size_t cell_index = 0; cell_index < row.size(); ++cell_index) {
            const auto &cell = row[cell_index];
            napi_value value = nullptr;
            if (cell.is_null) napi_get_null(env, &value);
            else value = make_string(env, cell.text);
            napi_set_element(env, cells, cell_index, value);
        }
        napi_set_element(env, rows, index, cells);
    }
    napi_set_named_property(env, object, "rows", rows);
    return object;
}

void execute_query(napi_env, void *data)
{
    auto &job = *static_cast<QueryWork *>(data);
    auto &status = job.executing_script ? job.script.summary : job.result;
    try {
        if (job.executing_script) {
            job.script = qfli_mysql::execute_script(job.socket, job.schema, job.source);
        } else {
            job.result = job.stopping
                ? qfli_mysql::shutdown(job.socket)
                : qfli_mysql::query(job.socket, job.schema, job.source, job.parameters);
        }
    } catch (const std::exception &error) {
        status.error_code = 1;
        status.error = error.what();
    } catch (...) {
        status.error_code = 1;
        status.error = "Oracle MySQL query failed.";
    }
}

void complete_query(napi_env env, napi_status status, void *data)
{
    std::unique_ptr<QueryWork> job(static_cast<QueryWork *>(data));
    auto &result = job->executing_script ? job->script.summary : job->result;
    if (status != napi_ok) {
        result.available = false;
        result.error_code = 1;
        result.error = "Oracle MySQL query was cancelled.";
    }
    napi_value encoded = encode_result(env, result);
    if (job->executing_script) {
        napi_value results = nullptr;
        napi_create_array_with_length(env, job->script.results.size(), &results);
        for (std::size_t index = 0; index < job->script.results.size(); ++index) {
            napi_set_element(env, results, index, encode_result(env, job->script.results[index]));
        }
        napi_set_named_property(env, encoded, "results", results);
    }
    napi_resolve_deferred(env, job->deferred, encoded);
    napi_delete_async_work(env, job->work);
}

napi_value queue_work(napi_env env, std::unique_ptr<QueryWork> job)
{
    napi_value promise = nullptr;
    napi_value resource_name = make_string(env, "qfli_mysql_query");
    if (napi_create_promise(env, &job->deferred, &promise) != napi_ok ||
        napi_create_async_work(env, nullptr, resource_name, execute_query, complete_query,
                               job.get(), &job->work) != napi_ok) {
        napi_throw_error(env, nullptr, "Could not create MySQL query work.");
        return nullptr;
    }
    if (napi_queue_async_work(env, job->work) != napi_ok) {
        napi_delete_async_work(env, job->work);
        napi_throw_error(env, nullptr, "Could not queue MySQL query work.");
        return nullptr;
    }
    job.release();
    return promise;
}

napi_value query(napi_env env, napi_callback_info info)
{
    try {
        auto job = std::make_unique<QueryWork>();
        std::size_t count = 4;
        napi_value arguments[4]{};
        bool is_array = false;
        if (napi_get_cb_info(env, info, &count, arguments, nullptr, nullptr) != napi_ok ||
            count != 4 || !read_string(env, arguments[0], job->socket) ||
            !read_string(env, arguments[1], job->schema) ||
            !read_string(env, arguments[2], job->source) ||
            napi_is_array(env, arguments[3], &is_array) != napi_ok || !is_array) {
            napi_throw_type_error(env, nullptr, "query(socket, schema, source, params) expects strings and an array.");
            return nullptr;
        }
        uint32_t parameter_count = 0;
        if (napi_get_array_length(env, arguments[3], &parameter_count) != napi_ok ||
            parameter_count > 65535) {
            napi_throw_range_error(env, nullptr, "Too many MySQL parameters.");
            return nullptr;
        }
        std::size_t parameter_bytes = 0;
        for (uint32_t index = 0; index < parameter_count; ++index) {
            napi_value value = nullptr;
            napi_valuetype type = napi_undefined;
            if (napi_get_element(env, arguments[3], index, &value) != napi_ok ||
                napi_typeof(env, value, &type) != napi_ok) {
                napi_throw_type_error(env, nullptr, "Invalid MySQL parameter.");
                return nullptr;
            }
            if (type == napi_null) {
                job->parameters.emplace_back(std::nullopt);
            } else {
                std::string parameter;
                if (!read_string(env, value, parameter) ||
                    parameter.size() > 1024 * 1024 - parameter_bytes) {
                    napi_throw_type_error(env, nullptr, "MySQL parameters must be nullable strings within the input limit.");
                    return nullptr;
                }
                parameter_bytes += parameter.size();
                job->parameters.emplace_back(std::move(parameter));
            }
        }
        return queue_work(env, std::move(job));
    } catch (const std::exception &error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

napi_value shutdown(napi_env env, napi_callback_info info)
{
    try {
        auto job = std::make_unique<QueryWork>();
        std::size_t count = 1;
        napi_value argument = nullptr;
        if (napi_get_cb_info(env, info, &count, &argument, nullptr, nullptr) != napi_ok ||
            count != 1 || !read_string(env, argument, job->socket)) {
            napi_throw_type_error(env, nullptr, "shutdown(socket) expects a string.");
            return nullptr;
        }
        job->stopping = true;
        return queue_work(env, std::move(job));
    } catch (const std::exception &error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

napi_value execute_script(napi_env env, napi_callback_info info)
{
    try {
        auto job = std::make_unique<QueryWork>();
        std::size_t count = 3;
        napi_value arguments[3]{};
        if (napi_get_cb_info(env, info, &count, arguments, nullptr, nullptr) != napi_ok ||
            count != 3 || !read_string(env, arguments[0], job->socket) ||
            !read_string(env, arguments[1], job->schema) ||
            !read_string(env, arguments[2], job->source)) {
            napi_throw_type_error(env, nullptr, "executeScript(socket, schema, source) expects strings.");
            return nullptr;
        }
        job->executing_script = true;
        return queue_work(env, std::move(job));
    } catch (const std::exception &error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

napi_value terminate_child(napi_env env, napi_callback_info info)
{
    std::size_t count = 1;
    napi_value argument = nullptr;
    int32_t pid = 0;
    if (napi_get_cb_info(env, info, &count, &argument, nullptr, nullptr) != napi_ok ||
        count != 1 || napi_get_value_int32(env, argument, &pid) != napi_ok || pid <= 1) {
        napi_throw_type_error(env, nullptr, "terminateChild(pid) expects a child process id.");
        return nullptr;
    }
    if (kill(pid, SIGTERM) != 0 && errno != ESRCH) {
        napi_throw_error(env, nullptr, std::strerror(errno));
        return nullptr;
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value is_child_running(napi_env env, napi_callback_info info)
{
    std::size_t count = 1;
    napi_value argument = nullptr;
    int32_t pid = 0;
    if (napi_get_cb_info(env, info, &count, &argument, nullptr, nullptr) != napi_ok ||
        count != 1 || napi_get_value_int32(env, argument, &pid) != napi_ok || pid <= 1) {
        napi_throw_type_error(env, nullptr, "isChildRunning(pid) expects a child process id.");
        return nullptr;
    }
    const bool running = kill(pid, 0) == 0 || errno == EPERM;
    napi_value result = nullptr;
    napi_get_boolean(env, running, &result);
    return result;
}

napi_value version(napi_env env, napi_callback_info)
{
    return make_string(env, qfli_mysql::client_version());
}

napi_value init(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        {"query", nullptr, query, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"executeScript", nullptr, execute_script, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shutdown", nullptr, shutdown, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"terminateChild", nullptr, terminate_child, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isChildRunning", nullptr, is_child_running, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"version", nullptr, version, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}

}  // namespace

static napi_module qfli_mysql_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = init,
    .nm_modname = "qfli_mysql",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void register_qfli_mysql_module()
{
    napi_module_register(&qfli_mysql_module);
}
