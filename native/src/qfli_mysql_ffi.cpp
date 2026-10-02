#include "qfli_mysql_ffi.h"
#include "qfli_mysql_client.h"

#include <rapidjson/document.h>
#include <rapidjson/stringbuffer.h>
#include <rapidjson/writer.h>

#include <cstdlib>
#include <cstring>
#include <stdexcept>

namespace {
using Writer = rapidjson::Writer<rapidjson::StringBuffer>;

void text(Writer &writer, const std::string &value)
{
    writer.String(value.data(), static_cast<rapidjson::SizeType>(value.size()));
}

void fields(Writer &writer, const qfli_mysql::QueryResult &result)
{
    writer.Key("available"); writer.Bool(result.available);
    writer.Key("exitCode"); writer.Uint(result.error_code);
    writer.Key("error"); text(writer, result.error);
    writer.Key("sqlState"); text(writer, result.sql_state);
    writer.Key("affectedRows"); writer.Uint64(result.affected_rows);
    writer.Key("truncated"); writer.Bool(result.truncated);
    writer.Key("columns"); writer.StartArray();
    for (const auto &column : result.columns) text(writer, column.name);
    writer.EndArray();
    writer.Key("columnInfo"); writer.StartArray();
    for (const auto &column : result.columns) {
        writer.StartObject();
        writer.Key("name"); text(writer, column.name);
        writer.Key("nativeType"); writer.Uint(column.native_type);
        writer.Key("binary"); writer.Bool(column.binary);
        writer.EndObject();
    }
    writer.EndArray();
    writer.Key("rows"); writer.StartArray();
    for (const auto &row : result.rows) {
        writer.StartArray();
        for (const auto &cell : row) {
            if (cell.is_null) writer.Null();
            else text(writer, cell.text);
        }
        writer.EndArray();
    }
    writer.EndArray();
}

std::string string_field(const rapidjson::Value &request, const char *name)
{
    if (!request.HasMember(name) || !request[name].IsString()) {
        throw std::invalid_argument(std::string("Missing string field: ") + name);
    }
    return {request[name].GetString(), request[name].GetStringLength()};
}

qfli_mysql::QueryLimits limits(const rapidjson::Value &request)
{
    qfli_mysql::QueryLimits value;
    if (request.HasMember("rowLimit")) {
        if (!request["rowLimit"].IsUint() || request["rowLimit"].GetUint() == 0 ||
            request["rowLimit"].GetUint() > value.rows) throw std::invalid_argument("Invalid row limit.");
        value.rows = request["rowLimit"].GetUint();
    }
    if (request.HasMember("byteLimit")) {
        if (!request["byteLimit"].IsUint() || request["byteLimit"].GetUint() == 0 ||
            request["byteLimit"].GetUint() > value.bytes) throw std::invalid_argument("Invalid byte limit.");
        value.bytes = request["byteLimit"].GetUint();
    }
    return value;
}

char *copy(const rapidjson::StringBuffer &buffer)
{
    auto *result = static_cast<char *>(std::malloc(buffer.GetSize() + 1));
    if (result) std::memcpy(result, buffer.GetString(), buffer.GetSize() + 1);
    return result;
}
} // namespace

extern "C" char *qfli_mysql_invoke(const char *input, size_t length)
{
    try {
        rapidjson::Document request;
        if (!input || length > 16 * 1024 * 1024) throw std::invalid_argument("Invalid MySQL request size.");
        request.Parse(input, length);
        if (request.HasParseError() || !request.IsObject()) throw std::invalid_argument("Invalid MySQL request JSON.");
        const auto method = string_field(request, "method");
        const auto socket = string_field(request, "socket");
        const auto password = string_field(request, "password");
        rapidjson::StringBuffer buffer;
        Writer writer(buffer);
        writer.StartObject();
        if (method == "shutdown") {
            fields(writer, qfli_mysql::shutdown(socket, password));
        } else {
            const auto schema = string_field(request, "schema");
            const auto source = string_field(request, "source");
            const auto caps = limits(request);
            if (method == "executeScript") {
                const auto result = qfli_mysql::execute_script(socket, schema, source, caps, password);
                fields(writer, result.summary);
                writer.Key("results"); writer.StartArray();
                for (const auto &item : result.results) {
                    writer.StartObject(); fields(writer, item); writer.EndObject();
                }
                writer.EndArray();
            } else if (method == "query") {
                if (!request.HasMember("params") || !request["params"].IsArray()) {
                    throw std::invalid_argument("Missing query parameters.");
                }
                std::vector<std::optional<std::string>> parameters;
                for (const auto &value : request["params"].GetArray()) {
                    if (value.IsNull()) parameters.emplace_back(std::nullopt);
                    else if (value.IsString()) parameters.emplace_back(std::string(value.GetString(), value.GetStringLength()));
                    else throw std::invalid_argument("Parameters must be strings or null.");
                }
                fields(writer, qfli_mysql::query(socket, schema, source, parameters, caps, password));
            } else throw std::invalid_argument("Unknown MySQL method.");
        }
        writer.EndObject();
        return copy(buffer);
    } catch (const std::exception &error) {
        qfli_mysql::QueryResult result;
        result.error_code = 1;
        result.error = error.what();
        rapidjson::StringBuffer buffer;
        Writer writer(buffer);
        writer.StartObject(); fields(writer, result); writer.EndObject();
        return copy(buffer);
    } catch (...) {
        return nullptr;
    }
}

extern "C" void qfli_mysql_free(char *result) { std::free(result); }
