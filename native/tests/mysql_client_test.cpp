#include "qfli_mysql_client.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <unistd.h>

namespace {

void require(bool condition, const char *message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

void success(const qfli_mysql::QueryResult &result)
{
    if (!result.available || result.error_code != 0) {
        std::cerr << result.error_code << " " << result.sql_state << " " << result.error << '\n';
        std::exit(1);
    }
}

}  // namespace

int main(int argc, char **argv)
{
    require(argc == 2, "pass the private test server socket path");
    const std::string socket = argv[1];
    const std::string schema = "qfli_client_test_" + std::to_string(getpid());
    auto run = [&](const std::string &source,
                   const std::vector<std::optional<std::string>> &parameters = {}) {
        auto result = qfli_mysql::query(socket, schema, source, parameters);
        success(result);
        return result;
    };
    auto version = qfli_mysql::query(socket, "", "SELECT VERSION(), @@version_comment");
    success(version);
    require(version.rows[0][0].text.find("MariaDB") == std::string::npos,
            "test engine must be Oracle MySQL");
    std::cout << "Oracle MySQL " << version.rows[0][0].text << " "
              << version.rows[0][1].text << '\n';
    success(qfli_mysql::query(socket, "", "CREATE DATABASE `" + schema + "`"));
    run("CREATE TABLE items (id BIGINT PRIMARY KEY, text_value TEXT, "
        "note TEXT NULL, exact_value DECIMAL(30,6), bytes BLOB)");
    auto insert = run("INSERT INTO items VALUES (?, ?, ?, ?, UNHEX(?))",
                      {"9007199254740993", "O'Brien", std::nullopt,
                       "123456789012345678901234.123456", "00FF4142"});
    require(insert.affected_rows == 1, "insert affected row count");
    auto selected = run("SELECT id, text_value, note, exact_value, bytes FROM items");
    require(selected.rows.size() == 1, "select row count");
    require(selected.rows[0][0].text == "9007199254740993", "exact large integer");
    require(selected.rows[0][1].text == "O'Brien", "bound quoted string");
    require(selected.rows[0][2].is_null, "SQL NULL remains distinct from text");
    require(selected.rows[0][3].text == "123456789012345678901234.123456", "exact decimal");
    require(selected.columns[4].binary && selected.rows[0][4].text == "00FF4142", "binary bytes");
    auto unchanged = run("UPDATE items SET text_value = ? WHERE id = ?",
                         {"O'Brien", "9007199254740993"});
    require(unchanged.affected_rows == 1, "CLIENT_FOUND_ROWS includes unchanged values");
    const std::string long_value(1500, 'x');
    run("UPDATE items SET text_value = ?", {long_value});
    require(run("SELECT text_value FROM items").rows[0][0].text == long_value,
            "refetch a cell larger than its initial result buffer");
    auto limited = qfli_mysql::query(socket, schema, "SELECT text_value FROM items", {}, {10, 100});
    success(limited);
    require(limited.truncated && limited.rows.empty(), "never publish a partial row");
    auto mismatch = qfli_mysql::query(socket, schema, "SELECT ?", {});
    require(mismatch.available && mismatch.error_code != 0, "reject parameter mismatch");
    auto malformed = qfli_mysql::query(socket, schema, "SELEC invalid");
    require(malformed.available && malformed.error_code != 0 && !malformed.error.empty(),
            "real SQL error with diagnostics");
    auto multiple = qfli_mysql::query(socket, schema, "SELECT 1; DROP TABLE items");
    require(multiple.available && multiple.error_code != 0, "query accepts one statement");
    require(run("SELECT COUNT(*) FROM items").rows[0][0].text == "1", "rejected script made no change");
    auto deleted = run("DELETE FROM items WHERE id = ?", {"9007199254740993"});
    require(deleted.affected_rows == 1, "delete affected row count");
    success(qfli_mysql::query(socket, "", "DROP DATABASE `" + schema + "`"));
    auto missing = qfli_mysql::query(socket + ".missing", "", "SELECT 1");
    require(!missing.available && missing.error_code != 0, "socket errors do not fall back to TCP");
    std::cout << "MySQL client round-trip tests passed.\n";
    return 0;
}
