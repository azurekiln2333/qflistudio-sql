#include "qfli_sql_validation.h"

#include <algorithm>
#include <chrono>
#include <memory>

#include "sqlite3.h"

namespace qfli_sql {
namespace {

using Clock = std::chrono::steady_clock;

struct ValidationGuard {
    Clock::time_point deadline = Clock::now() + std::chrono::milliseconds(250);
    std::string denied;
};

bool ascii_space(char value)
{
    return value == ' ' || value == '\t' || value == '\r' || value == '\n' ||
        value == '\v' || value == '\f';
}

std::string lowercase(std::string value)
{
    for (char &item : value) {
        if (item >= 'A' && item <= 'Z') item += 'a' - 'A';
    }
    return value;
}

// This only skips leading trivia, not SQL statement boundaries. SQLite's tail
// is the sole statement splitter, including for triggers and quoted semicolons.
std::size_t skip_trivia(const std::string &source, std::size_t offset)
{
    while (offset < source.size()) {
        if (ascii_space(source[offset]) || source[offset] == ';') {
            ++offset;
        } else if (source.compare(offset, 2, "--") == 0) {
            const std::size_t next = source.find('\n', offset + 2);
            offset = next == std::string::npos ? source.size() : next + 1;
        } else if (source.compare(offset, 2, "/*") == 0) {
            const std::size_t next = source.find("*/", offset + 2);
            offset = next == std::string::npos ? source.size() : next + 2;
        } else {
            break;
        }
    }
    return offset;
}

std::string keyword_at(const std::string &source, std::size_t offset)
{
    const std::size_t start = offset;
    while (offset < source.size() && offset - start < 32) {
        const char item = source[offset];
        if (!((item >= 'A' && item <= 'Z') || (item >= 'a' && item <= 'z'))) break;
        ++offset;
    }
    return source.substr(start, offset - start);
}

// SQLite error offsets are UTF-8 bytes. Editor positions are UTF-16 code units,
// with CRLF counting as two and supplementary characters counting as two.
int utf16_offset(const std::string &source, std::size_t offset)
{
    const std::size_t end = std::min(offset, source.size());
    std::size_t index = 0;
    int units = 0;
    while (index < end) {
        const unsigned char value = static_cast<unsigned char>(source[index]);
        const std::size_t width = value < 0x80 ? 1 : value >= 0xc2 && value <= 0xdf ? 2 :
            value >= 0xe0 && value <= 0xef ? 3 : value >= 0xf0 && value <= 0xf4 ? 4 : 0;
        if (width == 0 || index + width > end) break;
        for (std::size_t continuation = 1; continuation < width; ++continuation) {
            const unsigned char next = static_cast<unsigned char>(source[index + continuation]);
            if ((next & 0xc0) != 0x80) return units;
        }
        units += width == 4 ? 2 : 1;
        index += width;
    }
    return units;
}

int authorize(void *context, int action, const char *, const char *argument2, const char *, const char *)
{
    ValidationGuard *guard = static_cast<ValidationGuard *>(context);
    switch (action) {
        case SQLITE_PRAGMA: guard->denied = "PRAGMA"; break;
        case SQLITE_ATTACH: guard->denied = "ATTACH"; break;
        case SQLITE_DETACH: guard->denied = "DETACH"; break;
        case SQLITE_FUNCTION: {
            // A fresh connection has only bundled built-ins, with extensions
            // disabled and no registered application callbacks. Keep ordinary
            // scalar/aggregate syntax usable but deny external/file helpers.
            const std::string name = lowercase(argument2 == nullptr ? "" : argument2);
            if (name != "load_extension" && name != "readfile" && name != "writefile" &&
                name != "sqlite_readfile" && name != "sqlite_writefile" && name != "eval" &&
                name != "fts3_tokenizer" && name != "edit" && name != "shell") return SQLITE_OK;
            guard->denied = "External/file function calls";
            break;
        }
        case SQLITE_CREATE_VTABLE:
        case SQLITE_DROP_VTABLE: guard->denied = "virtual tables"; break;
        default: return SQLITE_OK;
    }
    return SQLITE_DENY;
}

int deadline_reached(void *context)
{
    return Clock::now() >= static_cast<ValidationGuard *>(context)->deadline ? 1 : 0;
}

bool schema_gap(const std::string &message)
{
    const std::string text = lowercase(message);
    const char *markers[] = {"no such table", "no such column", "no such function",
        "no such collation sequence", "no such index", "no such trigger", "no such view",
        "has no column named", "unknown database", "no such module"};
    for (const char *marker : markers) {
        if (text.find(marker) != std::string::npos) return true;
    }
    return false;
}

bool syntax_failure(int code, const std::string &message)
{
    if (code != SQLITE_ERROR) return false;
    const std::string text = lowercase(message);
    return text.find("syntax error") != std::string::npos ||
        text.find("unrecognized token") != std::string::npos || text == "incomplete input";
}

void skip_remaining(ValidationResult &result, const std::string &source,
    std::size_t start, const std::string &reason)
{
    ValidationSkipped skipped;
    skipped.start_offset = utf16_offset(source, start);
    skipped.end_offset = utf16_offset(source, source.size());
    skipped.keyword = keyword_at(source, start);
    skipped.reason = reason;
    result.skipped.push_back(skipped);
    result.truncated = true;
}

} // namespace

ValidationResult validate_sql(const std::string &source)
{
    ValidationResult result;
    result.version = sqlite3_libversion();
    if (source.size() > kValidationMaxBytes) {
        result.error = "SQLite syntax validation exceeds the 1 MiB source limit.";
        result.truncated = true;
        return result;
    }
    if (source.find('\0') != std::string::npos) {
        result.error = "SQLite syntax validation source cannot contain NUL.";
        return result;
    }

    sqlite3 *opened = nullptr;
    const int open_code = sqlite3_open_v2(":memory:", &opened,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nullptr);
    std::unique_ptr<sqlite3, decltype(&sqlite3_close)> database(opened, sqlite3_close);
    if (open_code != SQLITE_OK || opened == nullptr) {
        result.error = opened == nullptr ? "SQLite isolated database open failed." : sqlite3_errmsg(opened);
        return result;
    }
    ValidationGuard guard;
    sqlite3_db_config(opened, SQLITE_DBCONFIG_DEFENSIVE, 1, nullptr);
    sqlite3_db_config(opened, SQLITE_DBCONFIG_TRUSTED_SCHEMA, 0, nullptr);
    // Production additionally compiles SQLITE_OMIT_LOAD_EXTENSION. This keeps
    // the independent host-core test equally conservative when linked elsewhere.
    sqlite3_db_config(opened, SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, 0, nullptr);
    sqlite3_limit(opened, SQLITE_LIMIT_LENGTH, static_cast<int>(kValidationMaxBytes));
    sqlite3_limit(opened, SQLITE_LIMIT_SQL_LENGTH, static_cast<int>(kValidationMaxBytes));
    sqlite3_limit(opened, SQLITE_LIMIT_EXPR_DEPTH, 128);
    sqlite3_limit(opened, SQLITE_LIMIT_COLUMN, 256);
    sqlite3_limit(opened, SQLITE_LIMIT_COMPOUND_SELECT, 64);
    sqlite3_limit(opened, SQLITE_LIMIT_VARIABLE_NUMBER, 1000);
    sqlite3_limit(opened, SQLITE_LIMIT_FUNCTION_ARG, 100);
    sqlite3_limit(opened, SQLITE_LIMIT_ATTACHED, 0);
    sqlite3_limit(opened, SQLITE_LIMIT_VDBE_OP, 250000);
    if (sqlite3_set_authorizer(opened, authorize, &guard) != SQLITE_OK) {
        result.error = "SQLite validation authorizer could not be installed.";
        return result;
    }
    sqlite3_progress_handler(opened, 1000, deadline_reached, &guard);
    result.available = true;

    std::size_t cursor = 0;
    for (;;) {
        cursor = skip_trivia(source, cursor);
        if (cursor >= source.size()) break;
        if (result.checked >= kValidationMaxStatements || deadline_reached(&guard)) {
            ++result.statements; // one discovered remainder, not its unknown SQL count
            skip_remaining(result, source, cursor,
                "Validation stopped at its statement/time limit; this remaining range was not checked.");
            break;
        }
        sqlite3_stmt *prepared = nullptr;
        const char *tail = nullptr;
        const char *start = source.c_str() + cursor;
        guard.denied.clear();
        const int code = sqlite3_prepare_v2(opened, start,
            static_cast<int>(source.size() - cursor), &prepared, &tail);
        const int raw_offset = sqlite3_error_offset(opened);
        const std::string message = sqlite3_errmsg(opened);
        const bool has_statement = prepared != nullptr;
        if (prepared != nullptr) sqlite3_finalize(prepared);
        if (code == SQLITE_OK && !has_statement) break;
        ++result.statements;
        ++result.checked;
        if (code != SQLITE_OK) {
            std::string reason;
            if (!guard.denied.empty()) {
                reason = guard.denied + " is excluded from prepare-only validation for safety.";
            } else if (schema_gap(message)) {
                ++result.schema_gaps;
                reason = "The isolated validation database has no user schema: " + message;
            } else if (syntax_failure(code, message)) {
                ValidationIssue issue;
                const std::size_t byte_offset = raw_offset < 0 ? cursor :
                    cursor + std::min(static_cast<std::size_t>(raw_offset), source.size() - cursor);
                issue.start_offset = utf16_offset(source, byte_offset);
                issue.end_offset = issue.start_offset;
                issue.message = message;
                issue.code = raw_offset < 0 ? "sqlite-syntax" : "sqlite-syntax-offset";
                result.issues.push_back(issue);
                reason = "SQLite found a syntax error.";
            } else {
                reason = "SQLite preparation could not establish syntax coverage: " + message;
            }
            // A failure tail need not be a complete statement boundary. Never
            // resume at it or claim unseen statements were successfully parsed.
            skip_remaining(result, source, cursor,
                reason + " Preparation stopped; this range and any subsequent SQL are not fully checked.");
            break;
        }
        if (tail == nullptr || tail <= start || tail > source.c_str() + source.size()) {
            skip_remaining(result, source, cursor,
                "SQLite did not return a progressing statement boundary; remaining coverage is unavailable.");
            break;
        }
        cursor = static_cast<std::size_t>(tail - source.c_str());
    }
    // The callbacks contain stack-owned context; remove them before destruction.
    sqlite3_progress_handler(opened, 0, nullptr, nullptr);
    sqlite3_set_authorizer(opened, nullptr, nullptr);
    return result;
}

} // namespace qfli_sql
