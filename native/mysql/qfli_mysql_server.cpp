#include <AbilityKit/native_child_process.h>
#include "my_rapidjson_size_t.h"
#include <rapidjson/document.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <string>
#include <unistd.h>
#include <vector>

extern int mysqld_main(int argc, char **argv);

namespace {

std::string exit_file;

bool read_string(const rapidjson::Value &value, std::string &result)
{
    if (!value.IsString() || value.GetStringLength() == 0 ||
        value.GetStringLength() > 8192 ||
        std::memchr(value.GetString(), '\0', value.GetStringLength()) != nullptr) {
        return false;
    }
    result.assign(value.GetString(), value.GetStringLength());
    return true;
}

} // namespace

extern "C" __attribute__((visibility("default")))
void qfli_mysql_record_exit(int code)
{
    if (exit_file.empty()) return;
    const std::string temporary = exit_file + ".tmp";
    const int descriptor = open(temporary.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (descriptor < 0) {
        std::fprintf(stderr, "MySQL exit record open failed: %s\n", std::strerror(errno));
        return;
    }
    char text[32];
    const int length = std::snprintf(text, sizeof(text), "%d\n", code);
    std::size_t offset = 0;
    bool complete = true;
    while (offset < static_cast<std::size_t>(length)) {
        const ssize_t written = write(descriptor, text + offset, length - offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) {
            complete = false;
            break;
        }
        offset += static_cast<std::size_t>(written);
    }
    if (complete && fsync(descriptor) != 0) complete = false;
    if (close(descriptor) != 0) complete = false;
    if (complete && rename(temporary.c_str(), exit_file.c_str()) == 0) return;
    std::fprintf(stderr, "MySQL exit record write failed: %s\n", std::strerror(errno));
    unlink(temporary.c_str());
}

extern "C" __attribute__((visibility("default")))
void qfli_mysql_child_main(const char *entryParams)
{
    exit_file.clear();
    try {
        if (entryParams == nullptr || strnlen(entryParams, 256 * 1024 + 1) > 256 * 1024) {
            std::fprintf(stderr, "Missing or oversized MySQL child arguments\n");
            return;
        }
        rapidjson::Document request;
        request.Parse(entryParams);
        if (request.HasParseError() || !request.IsObject() ||
            !request.HasMember("exitFile") || !read_string(request["exitFile"], exit_file) ||
            exit_file.front() != '/' || exit_file.size() > 4090) {
            std::fprintf(stderr, "Invalid MySQL child exit file\n");
            return;
        }
        if (!request.HasMember("arguments") || !request["arguments"].IsArray() ||
            request["arguments"].Size() == 0 || request["arguments"].Size() > 64) {
            std::fprintf(stderr, "Invalid MySQL child arguments\n");
            qfli_mysql_record_exit(1);
            return;
        }
        if (request.HasMember("icuDataDirectory")) {
            std::string directory;
            if (!read_string(request["icuDataDirectory"], directory) ||
                directory.front() != '/' || setenv("ICU_DATA", directory.c_str(), 1) != 0) {
                std::fprintf(stderr, "Invalid MySQL ICU data directory\n");
                qfli_mysql_record_exit(1);
                return;
            }
        }
        std::vector<std::string> storage;
        storage.reserve(request["arguments"].Size());
        for (const auto &argument : request["arguments"].GetArray()) {
            std::string value;
            if (!read_string(argument, value)) {
                std::fprintf(stderr, "Invalid MySQL child argument value\n");
                qfli_mysql_record_exit(1);
                return;
            }
            storage.push_back(std::move(value));
        }
        std::vector<char *> argv;
        argv.reserve(storage.size() + 1);
        for (auto &value : storage) argv.push_back(value.data());
        argv.push_back(nullptr);
        const int result = mysqld_main(static_cast<int>(storage.size()), argv.data());
        qfli_mysql_record_exit(result);
    } catch (...) {
        std::fprintf(stderr, "MySQL child entry failed\n");
        qfli_mysql_record_exit(1);
    }
}

extern "C" __attribute__((visibility("default")))
void QfliMysqlMain(NativeChildProcess_Args args)
{
    qfli_mysql_child_main(args.entryParams);
}
