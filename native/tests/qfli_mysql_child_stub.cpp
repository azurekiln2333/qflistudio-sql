// Stub server entry used by the host lifecycle test. It mirrors the contract of
// native/mysql/qfli_mysql_server.cpp: parse the JSON exit file, honor a request
// to sleep, and record a numeric exit code.
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <string>
#include <unistd.h>

namespace {

void record_exit(const std::string &path, int code)
{
    if (path.empty()) return;
    const std::string temporary = path + ".tmp";
    const int descriptor = open(temporary.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (descriptor < 0) return;
    char text[32];
    const int length = std::snprintf(text, sizeof(text), "%d\n", code);
    ssize_t written = 0;
    while (written < length) {
        const ssize_t count = write(descriptor, text + written, length - written);
        if (count <= 0) break;
        written += count;
    }
    fsync(descriptor);
    close(descriptor);
    rename(temporary.c_str(), path.c_str());
}

// Minimal field extraction for the test's own JSON. The production entry uses
// RapidJSON; the test only needs "exitFile" and an optional "sleepSeconds".
std::string string_field(const std::string &json, const std::string &key)
{
    const std::string needle = "\"" + key + "\":\"";
    const std::size_t start = json.find(needle);
    if (start == std::string::npos) return {};
    const std::size_t begin = start + needle.size();
    const std::size_t end = json.find('"', begin);
    if (end == std::string::npos) return {};
    return json.substr(begin, end - begin);
}

int number_field(const std::string &json, const std::string &key, int fallback)
{
    const std::string needle = "\"" + key + "\":";
    const std::size_t start = json.find(needle);
    if (start == std::string::npos) return fallback;
    const std::size_t begin = start + needle.size();
    return std::atoi(json.c_str() + begin);
}

// Writes the list of open descriptors (from /proc/self/fd) to path. Used by the
// test to prove the fork child closed inherited parent descriptors before exec.
void report_open_descriptors(const std::string &path)
{
    if (path.empty()) return;
    DIR *directory = opendir("/proc/self/fd");
    if (directory == nullptr) return;
    const int directory_fd = dirfd(directory);
    std::string listing;
    for (;;) {
        struct dirent *entry = readdir(directory);
        if (entry == nullptr) break;
        if (entry->d_name[0] == '.') continue;
        // Do not report the descriptor used to read /proc/self/fd itself.
        if (std::atoi(entry->d_name) == directory_fd) continue;
        listing += entry->d_name;
        listing += '\n';
    }
    closedir(directory);
    const int out = open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (out < 0) return;
    if (!listing.empty()) {
        ssize_t written = 0;
        const ssize_t total = static_cast<ssize_t>(listing.size());
        while (written < total) {
            const ssize_t count = write(out, listing.data() + written, total - written);
            if (count <= 0) break;
            written += count;
        }
    }
    fsync(out);
    close(out);
}

} // namespace

extern "C" __attribute__((visibility("default")))
void qfli_mysql_child_main(const char *entryParams)
{
    if (entryParams == nullptr) {
        record_exit("", 1);
        return;
    }
    const std::string json(entryParams);
    const std::string exit_file = string_field(json, "exitFile");
    const int sleep_seconds = number_field(json, "sleepSeconds", 0);
    const int exit_code = number_field(json, "exitCode", 0);
    report_open_descriptors(string_field(json, "fdReport"));
    if (sleep_seconds > 0) sleep(static_cast<unsigned>(sleep_seconds));
    record_exit(exit_file, exit_code);
    exit(exit_code);
}
