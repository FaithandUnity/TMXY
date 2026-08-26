#include "tmxy/foundation/redaction.hpp"

#include <cstdlib>
#include <string>

namespace
{
int run_test()
{
    std::string database_value = "local";
    database_value += "-credential";
    std::string bearer_value = "header";
    bearer_value += "-credential";
    const std::string input = "postgresql://tmxy:" + database_value +
                              "@db/tmxy password=" + database_value + " Authorization=Bearer " +
                              bearer_value + " safe=value";
    const std::string redacted = tmxy::foundation::redact_sensitive_text(input);

    if (redacted.find(database_value) != std::string::npos ||
        redacted.find(bearer_value) != std::string::npos)
    {
        return EXIT_FAILURE;
    }
    if (redacted.find("safe=value") == std::string::npos ||
        redacted.find("<redacted>") == std::string::npos)
    {
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
} // namespace

int main()
{
    try
    {
        return run_test();
    }
    catch (...)
    {
        return EXIT_FAILURE;
    }
}
