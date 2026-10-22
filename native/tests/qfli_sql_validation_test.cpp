#include "qfli_sql_validation.h"
#include "sqlite3.h"

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

namespace {

int step_calls = 0;
int file_opens = 0;
int failures = 0;
sqlite3_vfs *real_vfs = nullptr;

void expect(bool condition, const std::string &message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

int audited_open(sqlite3_vfs *, const char *name, sqlite3_file *file, int flags, int *out_flags)
{
    ++file_opens;
    return real_vfs->xOpen(real_vfs, name, file, flags, out_flags);
}

std::string file_bytes(const std::string &path)
{
    std::ifstream file(path.c_str(), std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
}

bool exists(const std::string &path)
{
    std::ifstream file(path.c_str(), std::ios::binary);
    return file.good();
}

qfli_sql::ValidationResult validate(const std::string &source)
{
    step_calls = 0;
    file_opens = 0;
    qfli_sql::ValidationResult result = qfli_sql::validate_sql(source);
    expect(step_calls == 0, "production validator never calls sqlite3_step");
    expect(file_opens == 0, "production validator never opens a file through SQLite VFS");
    expect(result.checked <= result.statements, "checked count stays within discovered count");
    expect(result.schema_gaps <= result.checked, "schema gaps refer only to attempted statements");
    return result;
}

void expect_skipped(const std::string &source, const std::string &label)
{
    const auto result = validate(source);
    expect(result.available && result.checked == 1, label + " actually invokes SQLite prepare");
    expect(result.issues.empty(), label + " is not mislabeled a syntax error");
    expect(!result.skipped.empty() && result.truncated, label + " explicitly reports incomplete coverage");
}

} // namespace

extern "C" int __real_sqlite3_step(sqlite3_stmt *statement);
extern "C" int __wrap_sqlite3_step(sqlite3_stmt *statement)
{
    ++step_calls;
    return __real_sqlite3_step(statement);
}

int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    const std::string root = argv[1];
    const std::string existing = root + "/validation-owned.sqlite";
    const std::string attachment = root + "/validation-must-not-attach.sqlite";
    const std::string vacuum = root + "/validation-must-not-vacuum.sqlite";
    expect(!exists(existing) && !exists(attachment) && !exists(vacuum),
        "fixture paths are initially absent (unique build directory required)");
    if (failures != 0) return 1;

    real_vfs = sqlite3_vfs_find(nullptr);
    sqlite3_vfs audited = *real_vfs;
    audited.zName = "qfli-validation-audit";
    audited.pNext = nullptr;
    audited.xOpen = audited_open;
    expect(sqlite3_vfs_register(&audited, 1) == SQLITE_OK, "install real-engine file-open auditor");

    sqlite3 *fixture = nullptr;
    expect(sqlite3_open(existing.c_str(), &fixture) == SQLITE_OK, "create owned fixture database");
    expect(sqlite3_exec(fixture, "CREATE TABLE saved(value); INSERT INTO saved VALUES(7);",
        nullptr, nullptr, nullptr) == SQLITE_OK, "write baseline fixture outside validator");
    sqlite3_stmt *fixture_statement = nullptr;
    expect(sqlite3_prepare_v2(fixture, "SELECT value FROM saved", -1,
        &fixture_statement, nullptr) == SQLITE_OK, "prepare fixture for step auditor self-test");
    step_calls = 0;
    expect(sqlite3_step(fixture_statement) == SQLITE_ROW && step_calls == 1,
        "step auditor intercepts a genuine SQLite execution");
    sqlite3_finalize(fixture_statement);
    sqlite3_close(fixture);
    expect(file_opens > 0, "file auditor detects fixture file opens");
    const std::string before = file_bytes(existing);

    auto result = validate("-- only trivia\r\n /* comment */ ; ;");
    expect(result.available && !result.version.empty() && result.checked == 0 &&
        result.issues.empty() && !result.truncated, "empty/trivia source has honest engine availability");

    result = validate("SELECT 1; SELECT ';' AS delimiter; SELECT 3;");
    expect(result.available && result.checked == 3 && result.statements == 3 &&
        result.issues.empty() && result.skipped.empty() && !result.truncated,
        "all semicolon-containing literal statements prepare without executing");

    result = validate("CREATE TABLE fresh(value); INSERT INTO fresh VALUES(1); SELECT * FROM fresh;");
    expect(result.checked == 2 && result.schema_gaps == 1 && result.issues.empty() &&
        result.truncated && !result.skipped.empty(),
        "DDL was never executed: subsequent INSERT still sees a missing table; remaining SELECT unvalidated");
    expect_skipped("INSERT INTO absent VALUES(1);", "INSERT with absent schema");
    expect_skipped("UPDATE saved SET value=100;", "UPDATE cannot access the saved fixture");
    expect_skipped("DROP TABLE saved;", "DROP cannot access the saved fixture");
    expect_skipped("SELECT * FROM missing; SELEC 4;", "schema error stops before unseen syntax failure");
    expect_skipped("SELECT unknown_function(1);", "unavailable functions");
    result = validate("SELECT abs(-2), count(*), upper('safe');");
    expect(result.available && result.checked == 1 && result.issues.empty() &&
        result.skipped.empty() && !result.truncated,
        "ordinary bundled scalar and aggregate functions retain actual parser coverage");
    expect_skipped("CREATE VIRTUAL TABLE v USING fts5(value);", "virtual-table preparation");

    result = validate("SELECT 1;\r\n-- 中😀\r\nSELEC 2;");
    expect(result.issues.size() == 1 && result.checked == 2, "real parser diagnoses misspelled SELECT");
    if (!result.issues.empty()) {
        expect(result.issues[0].start_offset == 19 && result.issues[0].end_offset == 19,
            "UTF-8 error bytes convert to exact UTF-16 after CJK, emoji, and CRLF");
        expect(result.issues[0].code == "sqlite-syntax-offset", "real engine supplies a syntax error offset");
    }
    result = validate("SELECT '中😀' + FRM 1;");
    expect(result.issues.size() == 1 && result.issues[0].start_offset == 19,
        "syntax offset within a statement counts supplementary code points as two UTF-16 units");
    result = validate("SELECT (");
    expect(result.issues.size() == 1 && result.issues[0].start_offset == 0,
        "incomplete syntax with no SQLite offset uses a bounded insertion range");
    result = validate(std::string("SELECT 1;\0SELECT 2;", 19));
    expect(!result.available && result.checked == 0 && !result.error.empty(),
        "NUL source is rejected before preparation rather than shortened");
    result = validate(std::string(qfli_sql::kValidationMaxBytes + 1, ' '));
    expect(!result.available && result.checked == 0 && result.truncated && !result.error.empty(),
        "oversized source explicitly unavailable before preparation");
    std::string deep_expression = "SELECT 1";
    for (int index = 0; index < 200; ++index) deep_expression += "+1";
    result = validate(deep_expression + ";");
    expect(result.available && result.truncated && !result.skipped.empty(),
        "engine expression-depth bounds report limited coverage instead of a clean result");

    std::string many;
    for (int index = 0; index < qfli_sql::kValidationMaxStatements + 5; ++index) many += "SELECT 1;";
    result = validate(many);
    expect(result.checked == qfli_sql::kValidationMaxStatements && result.truncated &&
        result.statements == result.checked + 1 && result.skipped.size() == 1,
        "statement budget marks an unknown remaining coverage segment");

    expect_skipped("PRAGMA temp_store_directory='" + root + "';", "prepare-time PRAGMA");
    expect_skipped("EXPLAIN PRAGMA journal_mode=WAL;", "EXPLAIN-wrapped PRAGMA");
    expect_skipped("PRAGMA main.writable_schema=ON;", "schema-qualified PRAGMA");
    expect_skipped("ATTACH DATABASE '" + attachment + "' AS side;", "ATTACH");
    expect_skipped("EXPLAIN ATTACH DATABASE '" + existing + "' AS side;", "EXPLAIN ATTACH");
    expect_skipped("DETACH DATABASE main;", "DETACH");
    expect_skipped("SELECT load_extension('" + root + "/never-load');", "extension loading");
    expect_skipped("SELECT writefile('" + attachment + "','x');", "file-writing function");
    result = validate("VACUUM INTO '" + vacuum + "';");
    expect(result.available && result.issues.empty(), "VACUUM is prepared, never stepped");
    result = validate("CREATE TABLE only_prepared(value); CREATE INDEX x ON only_prepared(value);");
    expect(result.schema_gaps == 1, "CREATE TABLE is never applied even inside validation memory DB");

    expect(!exists(attachment) && !exists(vacuum), "ATTACH/function/VACUUM never create files");
    expect(file_bytes(existing) == before, "existing database bytes are unchanged by all user SQL");
    sqlite3_vfs_register(real_vfs, 1);
    sqlite3_vfs_unregister(&audited);
    std::remove(existing.c_str());
    if (failures != 0) return 1;
    std::cout << "PASS: real SQLite " << sqlite3_libversion()
        << " production validation core; no stepping/files, precise offsets, safe exclusions, limits and partial coverage\n";
    return 0;
}
