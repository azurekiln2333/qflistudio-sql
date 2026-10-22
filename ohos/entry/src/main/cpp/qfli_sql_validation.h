#ifndef QFLI_SQL_VALIDATION_H
#define QFLI_SQL_VALIDATION_H

#include <cstddef>
#include <string>
#include <vector>

namespace qfli_sql {

constexpr std::size_t kValidationMaxBytes = 1024 * 1024;
constexpr int kValidationMaxStatements = 512;

struct ValidationIssue {
    int start_offset = 0;
    int end_offset = 0;
    std::string message;
    std::string code;
    std::string severity = "error";
};

struct ValidationSkipped {
    int start_offset = 0;
    int end_offset = 0;
    std::string keyword;
    std::string reason;
};

struct ValidationResult {
    bool available = false;
    std::string version;
    // These are discovered/attempted counts, not a claimed total when truncated.
    // One additional uncounted tail segment is represented at the statement cap.
    int statements = 0;
    int checked = 0;
    int schema_gaps = 0;
    bool truncated = false;
    std::vector<ValidationIssue> issues;
    std::vector<ValidationSkipped> skipped;
    std::string error;
};

// The only accepted input is SQL text. Always opens its own :memory: database,
// prepares/finalizes without stepping, and never accepts a user database path.
ValidationResult validate_sql(const std::string &source);

} // namespace qfli_sql

#endif
