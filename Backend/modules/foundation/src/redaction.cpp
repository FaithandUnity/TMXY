#include "tmxy/foundation/redaction.hpp"

#include <regex>
#include <string>

namespace tmxy::foundation
{
namespace
{
std::string replace_all(const std::string& input, const std::regex& pattern,
                        std::string_view replacement)
{
    return std::regex_replace(input, pattern, std::string{replacement});
}
} // namespace

std::string redact_sensitive_text(std::string_view text)
{
    static const std::regex credential_uri{R"(([a-z][a-z0-9+.-]*://[^:/\s]+:)[^@/\s]+(@))",
                                           std::regex::ECMAScript | std::regex::icase};
    static const std::regex bearer_value{R"((\bbearer\s+)[A-Za-z0-9._~+/=-]+)",
                                         std::regex::ECMAScript | std::regex::icase};
    static const std::regex keyed_value{
        R"(((?:password|passwd|pwd|secret|token|api[_-]?key|authorization|cookie)\s*[=:]\s*)("[^"]*"|'[^']*'|[^\s,;]+))",
        std::regex::ECMAScript | std::regex::icase};

    std::string result{text};
    result = replace_all(result, credential_uri, "$1<redacted>$2");
    result = replace_all(result, bearer_value, "$1<redacted>");
    result = replace_all(result, keyed_value, "$1<redacted>");
    return result;
}
} // namespace tmxy::foundation
