#include "qfli_mysql_client.h"

#include <rapidjson/document.h>
#include <rapidjson/stringbuffer.h>
#include <rapidjson/writer.h>

#include <iostream>
#include <iterator>
#include <optional>
#include <string>
#include <vector>

int main(int argc, char **argv)
{
    if (argc != 2) return 1;
    const std::string input(std::istreambuf_iterator<char>(std::cin), {});
    rapidjson::Document request;
    request.Parse(input.data(), input.size());
    if (request.HasParseError() || !request.IsObject() ||
        !request.HasMember("schema") || !request["schema"].IsString() ||
        !request.HasMember("source") || !request["source"].IsString() ||
        !request.HasMember("params") || !request["params"].IsArray()) {
        std::cerr << "Invalid query bridge request.\n";
        return 1;
    }
    std::vector<std::optional<std::string>> parameters;
    for (const auto &value : request["params"].GetArray()) {
        if (value.IsNull()) {
            parameters.emplace_back(std::nullopt);
        } else if (value.IsString()) {
            parameters.emplace_back(std::string(value.GetString(), value.GetStringLength()));
        } else {
            return 1;
        }
    }
    const auto result = qfli_mysql::query(
        argv[1], {request["schema"].GetString(), request["schema"].GetStringLength()},
        {request["source"].GetString(), request["source"].GetStringLength()}, parameters);
    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    writer.StartObject();
    writer.Key("available"); writer.Bool(result.available);
    writer.Key("exitCode"); writer.Uint(result.error_code);
    writer.Key("error"); writer.String(result.error.data(), result.error.size());
    writer.Key("affectedRows"); writer.Uint64(result.affected_rows);
    writer.Key("truncated"); writer.Bool(result.truncated);
    writer.Key("columns"); writer.StartArray();
    for (const auto &column : result.columns) {
        writer.String(column.name.data(), column.name.size());
    }
    writer.EndArray();
    writer.Key("rows"); writer.StartArray();
    for (const auto &row : result.rows) {
        writer.StartArray();
        for (const auto &cell : row) {
            if (cell.is_null) writer.Null();
            else writer.String(cell.text.data(), cell.text.size());
        }
        writer.EndArray();
    }
    writer.EndArray();
    writer.EndObject();
    std::cout.write(buffer.GetString(), buffer.GetSize());
    return 0;
}
