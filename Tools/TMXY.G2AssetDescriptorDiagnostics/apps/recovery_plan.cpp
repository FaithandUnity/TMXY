#include "recovery_plan.hpp"

#include <algorithm>
#include <fstream>
#include <ranges>
#include <stdexcept>
#include <string>
#include <vector>

namespace tmxy::g2_asset_descriptor_diagnostics
{
namespace
{

[[nodiscard]] bool is_sha256(const std::string_view value) noexcept
{
    return value.size() == 64U &&
           std::ranges::all_of(value,
                               [](const char character)
                               {
                                   return (character >= '0' && character <= '9') ||
                                          (character >= 'a' && character <= 'f');
                               });
}

[[nodiscard]] std::vector<std::string> split(const std::string& line)
{
    std::vector<std::string> fields;
    std::size_t start = 0;
    while (true)
    {
        const auto end = line.find('\t', start);
        fields.push_back(
            line.substr(start, end == std::string::npos ? std::string::npos : end - start));
        if (end == std::string::npos)
        {
            return fields;
        }
        start = end + 1U;
    }
}

[[nodiscard]] bool valid_kind(const std::string_view family, const std::string_view kind,
                              const std::string_view error) noexcept
{
    return (family == "qtx" &&
            (kind == "qtx_complete_mip_chain" || kind == "qtx_declared_mip_payload_prefix") &&
            error == "payload_size_mismatch") ||
           (family == "anim" && kind == "anim_payload_frame_counts" &&
            error == "frame_count_mismatch");
}

} // namespace

RecoveryPlan RecoveryPlan::read(const std::string& path)
{
    std::ifstream input(path, std::ios::binary);
    if (!input)
    {
        throw std::runtime_error("recovery_plan_unreadable");
    }
    RecoveryPlan result;
    std::string line;
    while (std::getline(input, line))
    {
        if (!line.empty() && line.back() == '\r')
        {
            line.pop_back();
        }
        const auto fields = split(line);
        if (fields.size() != 7U || !is_sha256(fields[0]) || !is_sha256(fields[1]) ||
            !is_sha256(fields[2]) || !is_sha256(fields[3]) ||
            !valid_kind(fields[4], fields[5], fields[6]))
        {
            throw std::runtime_error("recovery_plan_invalid");
        }
        RecoveryDirective directive{.asset_id = fields[0],
                                    .candidate_id = fields[1],
                                    .body_sha256 = fields[2],
                                    .source_sha256 = fields[3],
                                    .family = fields[4],
                                    .recovery_kind = fields[5],
                                    .strict_error_code = fields[6]};
        const Key key{directive.asset_id, directive.candidate_id};
        if (!result.directives_.emplace(key, std::move(directive)).second)
        {
            throw std::runtime_error("recovery_plan_duplicate");
        }
    }
    if (!input.eof())
    {
        throw std::runtime_error("recovery_plan_read_failed");
    }
    return result;
}

RecoveryDirective* RecoveryPlan::find(const std::string_view asset_id,
                                      const std::string_view candidate_id)
{
    const auto found = directives_.find({std::string(asset_id), std::string(candidate_id)});
    if (found == directives_.end())
    {
        return nullptr;
    }
    found->second.visited = true;
    return &found->second;
}

void RecoveryPlan::require_complete() const
{
    if (std::ranges::any_of(directives_, [](const auto& entry) { return !entry.second.visited; }))
    {
        throw std::runtime_error("recovery_plan_scope_drift");
    }
}

std::size_t RecoveryPlan::size() const noexcept
{
    return directives_.size();
}

} // namespace tmxy::g2_asset_descriptor_diagnostics
