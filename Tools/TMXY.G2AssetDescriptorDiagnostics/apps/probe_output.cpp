#include "probe_output.hpp"

#include <iostream>
#include <optional>
#include <string_view>
#include <utility>

namespace tmxy::g2_asset_descriptor_diagnostics
{
namespace
{

void append_json_string(std::ostream& output, const std::string_view value)
{
    constexpr std::string_view digits = "0123456789abcdef";
    output << '"';
    for (const char character : value)
    {
        const auto byte = static_cast<unsigned char>(character);
        switch (byte)
        {
        case '"':
            output << "\\\"";
            break;
        case '\\':
            output << "\\\\";
            break;
        case '\b':
            output << "\\b";
            break;
        case '\f':
            output << "\\f";
            break;
        case '\n':
            output << "\\n";
            break;
        case '\r':
            output << "\\r";
            break;
        case '\t':
            output << "\\t";
            break;
        default:
            if (byte < 0x20U)
            {
                output << "\\u00" << digits[byte >> 4U] << digits[byte & 0x0FU];
            }
            else
            {
                output << static_cast<char>(byte);
            }
        }
    }
    output << '"';
}

void append_optional_string(std::ostream& output, const std::optional<std::string>& value)
{
    if (value.has_value())
    {
        append_json_string(output, *value);
    }
    else
    {
        output << "null";
    }
}

} // namespace

void emit_result(const AssetResult& result)
{
    std::cout << R"({"asset_id":)";
    append_json_string(std::cout, result.asset_id);
    std::cout << R"(,"family":)";
    append_json_string(std::cout, result.family);
    std::cout << R"(,"structure":)";
    append_json_string(std::cout, result.structure);
    std::cout << R"(,"candidate_set_sha256":)";
    append_json_string(std::cout, result.candidate_set_sha256);
    std::cout << R"(,"candidates":[)";
    bool first = true;
    for (const auto& candidate : result.candidates)
    {
        if (!std::exchange(first, false))
        {
            std::cout << ',';
        }
        std::cout << R"({"candidate_id":)";
        append_json_string(std::cout, candidate.candidate_id);
        std::cout << R"(,"body_sha256":)";
        append_json_string(std::cout, candidate.body_sha256);
        std::cout << R"(,"descriptor":")" << (candidate.descriptor_parsed ? "PARSED" : "REJECTED")
                  << R"(","binding":")" << (candidate.strict_binding_passed ? "PASS" : "REJECTED")
                  << R"(","effective_binding":")"
                  << (candidate.effective_binding_passed ? "PASS" : "REJECTED")
                  << R"(","recovery_applied":)" << (candidate.recovery_applied ? "true" : "false")
                  << R"(,"recovery_kind":)";
        append_json_string(std::cout, candidate.recovery_kind);
        std::cout << R"(,"semantic_sha256":)";
        append_optional_string(std::cout, candidate.semantic_sha256);
        std::cout << R"(,"effective_semantic_sha256":)";
        append_optional_string(std::cout, candidate.effective_semantic_sha256);
        std::cout << R"(,"descriptor_semantic_sha256":)";
        append_optional_string(std::cout, candidate.descriptor_semantic_sha256);
        std::cout << R"(,"identity_normalized_semantic_sha256":)";
        append_optional_string(std::cout, candidate.identity_normalized_semantic_sha256);
        std::cout << R"(,"identity_normalized_descriptor_semantic_sha256":)";
        append_optional_string(std::cout, candidate.identity_normalized_descriptor_semantic_sha256);
        std::cout << R"(,"identity_mirror_ascii_lower_match":)"
                  << (candidate.identity_mirror_ascii_lower_match ? "true" : "false") << '}';
    }
    const auto& count = result.counts;
    std::cout << R"(],"counts":{"candidates":)" << count.candidates << R"(,"descriptor_parsed":)"
              << count.descriptor_parsed << R"(,"descriptor_rejected":)"
              << count.descriptor_rejected << R"(,"binding_pass":)" << count.binding_pass
              << R"(,"binding_rejected":)" << count.binding_rejected
              << R"(,"effective_binding_pass":)" << count.effective_binding_pass
              << R"(,"effective_binding_rejected":)" << count.effective_binding_rejected
              << R"(,"recovery_applied":)" << count.recovery_applied << R"(,"semantic_distinct":)"
              << count.semantic_distinct << R"(,"effective_semantic_distinct":)"
              << count.effective_semantic_distinct << "}}\n";
}

} // namespace tmxy::g2_asset_descriptor_diagnostics
