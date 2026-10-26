#include "napi/native_api.h"
#include "qfli_mysql_client.h"
#include "qfli_mysql_host.h"

#include <dlfcn.h>
#include <signal.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <sys/stat.h>

#if __has_include(<mysql.h>)
#include <mysql.h>
#define QFLI_HAS_MYSQL_TCP_CLIENT 1
#endif

#include <cerrno>
#include <cstring>
#include <exception>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "qfli_mysql_proto_probe.h"

namespace {

// Resolve the installed native library directory from this module's own loaded
// image. The packaged launcher and server library live beside it, so no
// writable data path is ever used as executable code.
std::string native_library_directory()
{
    Dl_info information{};
    if (dladdr(reinterpret_cast<void *>(&native_library_directory), &information) != 0 &&
        information.dli_fname != nullptr) {
        std::string path(information.dli_fname);
        const std::size_t slash = path.find_last_of('/');
        if (slash != std::string::npos) return path.substr(0, slash);
    }
    return {};
}

struct QueryWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string socket;
    std::string schema;
    std::string source;
    std::string password;
    std::vector<std::optional<std::string>> parameters;
    qfli_mysql::QueryResult result;
    qfli_mysql::ScriptResult script;
    bool stopping = false;
    bool executing_script = false;
    bool probing_sharing = false;
};

qfli_mysql::QueryResult probe_sharing(const std::string &password)
{
    qfli_mysql::QueryResult result;
    result.error_code = 1;
    result.error = "Authenticated loopback connection to 127.0.0.1:3306 failed.";
#ifdef QFLI_HAS_MYSQL_TCP_CLIENT
    struct ThreadScope {
        bool initialized = mysql_thread_init() == 0;
        ~ThreadScope() { if (initialized) mysql_thread_end(); }
    } thread;
    if (!thread.initialized) return result;
    std::unique_ptr<MYSQL, decltype(&mysql_close)> connection(mysql_init(nullptr), mysql_close);
    if (!connection) return result;
    const unsigned int timeout = 3;
    const auto protocol = MYSQL_PROTOCOL_TCP;
    const auto ssl_mode = SSL_MODE_DISABLED;
    const bool public_key = true;
    if (mysql_options(connection.get(), MYSQL_OPT_PROTOCOL, &protocol) != 0 ||
        mysql_options(connection.get(), MYSQL_OPT_CONNECT_TIMEOUT, &timeout) != 0 ||
        mysql_options(connection.get(), MYSQL_OPT_READ_TIMEOUT, &timeout) != 0 ||
        mysql_options(connection.get(), MYSQL_OPT_WRITE_TIMEOUT, &timeout) != 0 ||
        mysql_options(connection.get(), MYSQL_OPT_SSL_MODE, &ssl_mode) != 0 ||
        mysql_options(connection.get(), MYSQL_OPT_GET_SERVER_PUBLIC_KEY, &public_key) != 0 ||
        !mysql_real_connect(connection.get(), "127.0.0.1", "qfli_app", password.c_str(),
                            "qfli_shared", 3306, nullptr, 0)) return result;
    if (mysql_query(connection.get(),
        "SELECT VERSION(), @@port, @@bind_address, @@skip_networking, DATABASE(), CURRENT_USER()") != 0)
        return result;
    std::unique_ptr<MYSQL_RES, decltype(&mysql_free_result)> rows(
        mysql_store_result(connection.get()), mysql_free_result);
    if (!rows || mysql_num_fields(rows.get()) != 6) return result;
    MYSQL_ROW row = mysql_fetch_row(rows.get());
    if (!row) return result;
    std::vector<qfli_mysql::Cell> cells;
    for (unsigned int index = 0; index < 6; ++index) {
        cells.push_back({row[index] == nullptr, row[index] == nullptr ? "" : row[index]});
    }
    result.rows.push_back(std::move(cells));
    result.available = true;
    result.error_code = 0;
    result.error.clear();
#endif
    return result;
}

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
        if (job.probing_sharing) {
            job.result = probe_sharing(job.password);
        } else if (job.executing_script) {
            job.script = qfli_mysql::execute_script(job.socket, job.schema, job.source, {}, job.password);
        } else {
            job.result = job.stopping
                ? qfli_mysql::shutdown(job.socket, job.password)
                : qfli_mysql::query(job.socket, job.schema, job.source, job.parameters, {}, job.password);
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
        std::size_t count = 5;
        napi_value arguments[5]{};
        bool is_array = false;
        if (napi_get_cb_info(env, info, &count, arguments, nullptr, nullptr) != napi_ok ||
            (count != 4 && count != 5) || !read_string(env, arguments[0], job->socket) ||
            !read_string(env, arguments[1], job->schema) ||
            !read_string(env, arguments[2], job->source) ||
            napi_is_array(env, arguments[3], &is_array) != napi_ok || !is_array) {
            napi_throw_type_error(env, nullptr, "query(socket, schema, source, params) expects strings and an array.");
            return nullptr;
        }
        if (count == 5 && !read_string(env, arguments[4], job->password)) {
            napi_throw_type_error(env, nullptr, "MySQL password must be a string.");
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
        std::size_t count = 2;
        napi_value arguments[2]{};
        if (napi_get_cb_info(env, info, &count, arguments, nullptr, nullptr) != napi_ok ||
            (count != 1 && count != 2) || !read_string(env, arguments[0], job->socket) ||
            (count == 2 && !read_string(env, arguments[1], job->password))) {
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
        std::size_t count = 4;
        napi_value arguments[4]{};
        if (napi_get_cb_info(env, info, &count, arguments, nullptr, nullptr) != napi_ok ||
            (count != 3 && count != 4) || !read_string(env, arguments[0], job->socket) ||
            !read_string(env, arguments[1], job->schema) ||
            !read_string(env, arguments[2], job->source) ||
            (count == 4 && !read_string(env, arguments[3], job->password))) {
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

napi_value sharing_probe(napi_env env, napi_callback_info info)
{
    auto job = std::make_unique<QueryWork>();
    std::size_t count = 1;
    napi_value argument = nullptr;
    if (napi_get_cb_info(env, info, &count, &argument, nullptr, nullptr) != napi_ok ||
        count != 1 || !read_string(env, argument, job->password) || job->password.empty()) {
        napi_throw_type_error(env, nullptr, "sharingProbe requires a password.");
        return nullptr;
    }
    job->probing_sharing = true;
    return queue_work(env, std::move(job));
}

napi_value loopback_port_available(napi_env env, napi_callback_info)
{
    const int descriptor = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (descriptor < 0) {
        napi_throw_error(env, nullptr, "Could not inspect loopback port 3306.");
        return nullptr;
    }
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(3306);
    const int reuse = 1;
    if (setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) != 0) {
        close(descriptor);
        napi_throw_error(env, nullptr, "Could not inspect loopback port 3306.");
        return nullptr;
    }
    const bool available = bind(descriptor, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0;
    close(descriptor);
    napi_value result = nullptr;
    napi_get_boolean(env, available, &result);
    return result;
}

napi_value protect_file(napi_env env, napi_callback_info info)
{
    std::size_t count = 1;
    napi_value argument = nullptr;
    int32_t descriptor = -1;
    if (napi_get_cb_info(env, info, &count, &argument, nullptr, nullptr) != napi_ok ||
        count != 1 || napi_get_value_int32(env, argument, &descriptor) != napi_ok ||
        descriptor < 0 || fchmod(descriptor, 0600) != 0) {
        napi_throw_error(env, nullptr, "Could not protect MySQL credentials.");
        return nullptr;
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value signal_child(napi_env env, napi_callback_info info)
{
    std::size_t count = 2;
    napi_value arguments[2]{};
    int32_t pid = 0;
    bool force = false;
    if (napi_get_cb_info(env, info, &count, arguments, nullptr, nullptr) != napi_ok ||
        count != 2 || napi_get_value_int32(env, arguments[0], &pid) != napi_ok || pid <= 1 ||
        napi_get_value_bool(env, arguments[1], &force) != napi_ok) {
        napi_throw_type_error(env, nullptr, "signalChild(pid, force) expects a child id and a boolean.");
        return nullptr;
    }
    if (qfli_mysql::signal_child(pid, force) != 0) {
        napi_throw_error(env, nullptr, "Unknown MySQL child process.");
        return nullptr;
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

// pollChild(pid) -> { state: 'unknown'|'running'|'exited', exitCode: number }
// Typed so a successful exit 0 is never confused with a running child.
napi_value poll_child(napi_env env, napi_callback_info info)
{
    std::size_t count = 1;
    napi_value argument = nullptr;
    int32_t pid = 0;
    if (napi_get_cb_info(env, info, &count, &argument, nullptr, nullptr) != napi_ok ||
        count != 1 || napi_get_value_int32(env, argument, &pid) != napi_ok || pid <= 1) {
        napi_throw_type_error(env, nullptr, "pollChild(pid) expects a child process id.");
        return nullptr;
    }
    const qfli_mysql::ChildStatus status = qfli_mysql::poll_child(pid);
    napi_value object = nullptr;
    napi_create_object(env, &object);
    const char *state = status.state == qfli_mysql::ChildState::Running ? "running"
        : status.state == qfli_mysql::ChildState::Exited ? "exited" : "unknown";
    napi_set_named_property(env, object, "state", make_string(env, state));
    napi_value code = nullptr;
    napi_create_int32(env, status.exit_code, &code);
    napi_set_named_property(env, object, "exitCode", code);
    return object;
}

// completeRegisteredChild(pid, exitCode) -> void
// Marks a native-child-API child complete after its exit record is observed.
napi_value complete_registered_child(napi_env env, napi_callback_info info)
{
    std::size_t count = 2;
    napi_value arguments[2]{};
    int32_t pid = 0;
    int32_t exit_code = 0;
    if (napi_get_cb_info(env, info, &count, arguments, nullptr, nullptr) != napi_ok ||
        count != 2 || napi_get_value_int32(env, arguments[0], &pid) != napi_ok || pid <= 1 ||
        napi_get_value_int32(env, arguments[1], &exit_code) != napi_ok) {
        napi_throw_type_error(env, nullptr, "completeRegisteredChild(pid, exitCode) expects two integers.");
        return nullptr;
    }
    if (qfli_mysql::complete_registered_child(pid, exit_code) != 0) {
        napi_throw_error(env, nullptr, "Unknown or still-running MySQL child process.");
        return nullptr;
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value version(napi_env env, napi_callback_info)
{
    return make_string(env, qfli_mysql::client_version());
}

napi_value proto_probe(napi_env env, napi_callback_info info)
{
    try {
        (void)info;
        const std::string directory = native_library_directory();
        if (directory.empty()) {
            napi_throw_error(env, nullptr, "Could not resolve the native directory.");
            return nullptr;
        }
        const std::string library_path = directory + "/libqfli_mysql_server_proto.so";
        ProtoResult result;
        qfli_mysql_proto_probe(library_path.c_str(), &result);
        napi_value object = nullptr;
        napi_create_object(env, &object);
        set_boolean(env, object, "loaded", result.loaded);
        set_boolean(env, object, "ready", result.ready);
        set_number(env, object, "threadCalls", result.threadCalls);
        set_number(env, object, "atforkCalls", result.atforkCalls);
        set_number(env, object, "exitIntercepts", result.exitIntercepts);
        set_boolean(env, object, "childExitIsolated", result.childExitIsolated);
        set_number(env, object, "childPid", result.childPid);
        set_boolean(env, object, "owned", result.owned);
        set_number(env, object, "pendingPid", result.pendingPid);
        napi_set_named_property(env, object, "error", make_string(env, result.error));
        return object;
    } catch (const std::exception &error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

// preloadStart(entryParams) -> { pid, error }. DEBUG-only: loads the private
// server DSO and starts the server in a forked child by calling its entry
// directly (no exec). Used for the isolated debug-root probe.
napi_value preload_start(napi_env env, napi_callback_info info)
{
    try {
        std::size_t count = 1;
        napi_value argument = nullptr;
        std::string entry_params;
        if (napi_get_cb_info(env, info, &count, &argument, nullptr, nullptr) != napi_ok ||
            count != 1 || !read_string(env, argument, entry_params)) {
            napi_throw_type_error(env, nullptr, "preloadStart(entryParams) expects a string.");
            return nullptr;
        }
        const std::string directory = native_library_directory();
        if (directory.empty()) {
            napi_throw_error(env, nullptr, "Could not resolve the native directory.");
            return nullptr;
        }
        const std::string library_path = directory + "/libqfli_mysql_server_proto.so";
        ProtoResult result;
        const int pid = qfli_mysql_preload_start(library_path.c_str(), entry_params.c_str(),
                                                 &result);
        napi_value object = nullptr;
        napi_create_object(env, &object);
        set_number(env, object, "pid", pid);
        set_boolean(env, object, "failed", pid <= 1);
        set_boolean(env, object, "owned", result.owned);
        set_number(env, object, "pendingPid", result.pendingPid);
        set_number(env, object, "errno", pid <= 1 ? errno : 0);
        napi_set_named_property(env, object, "error", make_string(env, result.error));
        return object;
    } catch (const std::exception &error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

// startChild(entryParamsJson, logPath) -> pid
//
// Forks and execs the packaged launcher beside this module, passing the server
// entry JSON. Used on phones, where the native-child API is unavailable.
napi_value start_child(napi_env env, napi_callback_info info)
{
    try {
        std::size_t count = 2;
        napi_value arguments[2]{};
        std::string entry_params;
        std::string log_path;
        if (napi_get_cb_info(env, info, &count, arguments, nullptr, nullptr) != napi_ok ||
            count != 2 || !read_string(env, arguments[0], entry_params) ||
            !read_string(env, arguments[1], log_path)) {
            napi_throw_type_error(env, nullptr, "startChild(entryParams, logPath) expects two strings.");
            return nullptr;
        }
        const std::string directory = native_library_directory();
        if (directory.empty()) {
            napi_throw_error(env, nullptr, "Could not resolve the MySQL native library directory.");
            return nullptr;
        }
        const qfli_mysql::StartResult started =
            qfli_mysql::start_child(directory + "/libqfli_mysql_launcher.so",
                                    entry_params, log_path);
        napi_value result = nullptr;
        napi_create_object(env, &result);
        set_number(env, result, "pid", started.pid);
        set_boolean(env, result, "failed", !started.succeeded());
        // When a failed start could not confirm termination, the child is still
        // owned and must be cleaned through stop()/dispose(); surface its pid.
        set_boolean(env, result, "owned", started.owned);
        set_number(env, result, "pendingPid", started.pending_pid);
        set_number(env, result, "errno", started.succeeded() ? 0 : errno);
        napi_set_named_property(env, result, "error",
            make_string(env, started.succeeded() ? std::string() : std::strerror(errno)));
        return result;
    } catch (const std::exception &error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

// registerChild(pid) -> void
// Registers a child started by another host (the HarmonyOS native-child API),
// so terminate/poll manage it through the same owned-child table.
napi_value register_child(napi_env env, napi_callback_info info)
{
    std::size_t count = 1;
    napi_value argument = nullptr;
    int32_t pid = 0;
    if (napi_get_cb_info(env, info, &count, &argument, nullptr, nullptr) != napi_ok ||
        count != 1 || napi_get_value_int32(env, argument, &pid) != napi_ok || pid <= 1) {
        napi_throw_type_error(env, nullptr, "registerChild(pid) expects a child process id.");
        return nullptr;
    }
    if (qfli_mysql::register_child(pid) != 0) {
        napi_throw_error(env, nullptr, std::strerror(errno));
        return nullptr;
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

// releaseChild(pid) -> void
// Releases a completed child's retained status. Rejects a running child.
napi_value release_child(napi_env env, napi_callback_info info)
{
    std::size_t count = 1;
    napi_value argument = nullptr;
    int32_t pid = 0;
    if (napi_get_cb_info(env, info, &count, &argument, nullptr, nullptr) != napi_ok ||
        count != 1 || napi_get_value_int32(env, argument, &pid) != napi_ok || pid <= 1) {
        napi_throw_type_error(env, nullptr, "releaseChild(pid) expects a child process id.");
        return nullptr;
    }
    if (qfli_mysql::release_child(pid) != 0) {
        napi_throw_error(env, nullptr, "Unknown or still-running MySQL child process.");
        return nullptr;
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value init(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        {"query", nullptr, query, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"executeScript", nullptr, execute_script, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shutdown", nullptr, shutdown, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"sharingProbe", nullptr, sharing_probe, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loopbackPortAvailable", nullptr, loopback_port_available, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"protectFile", nullptr, protect_file, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startChild", nullptr, start_child, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"registerChild", nullptr, register_child, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"completeRegisteredChild", nullptr, complete_registered_child, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"releaseChild", nullptr, release_child, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pollChild", nullptr, poll_child, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"signalChild", nullptr, signal_child, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"version", nullptr, version, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"protoProbe", nullptr, proto_probe, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"preloadStart", nullptr, preload_start, nullptr, nullptr, nullptr, napi_default, nullptr},
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
