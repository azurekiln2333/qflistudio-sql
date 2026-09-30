#include "qfli_mysql_client.h"

namespace qfli_mysql {
namespace {
QueryResult unavailable()
{
    QueryResult result;
    result.error_code = 127;
    result.error = "The bundled Oracle MySQL runtime requires a HarmonyOS arm64 device.";
    return result;
}
}  // namespace

QueryResult query(const std::string &, const std::string &, const std::string &,
                  const std::vector<std::optional<std::string>> &, QueryLimits)
{
    return unavailable();
}

QueryResult shutdown(const std::string &)
{
    return unavailable();
}

ScriptResult execute_script(const std::string &, const std::string &,
                            const std::string &, QueryLimits)
{
    return {unavailable(), {}};
}

const char *client_version()
{
    return "";
}
}  // namespace qfli_mysql
