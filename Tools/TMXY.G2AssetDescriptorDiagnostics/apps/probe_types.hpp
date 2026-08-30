#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace tmxy::g2_asset_descriptor_diagnostics
{

struct CandidateResult final
{
    std::string candidate_id;
    std::string body_sha256;
    bool descriptor_parsed{false};
    bool strict_binding_passed{false};
    bool effective_binding_passed{false};
    bool recovery_applied{false};
    std::string recovery_kind{"none"};
    std::optional<std::string> semantic_sha256;
    std::optional<std::string> effective_semantic_sha256;
    std::optional<std::string> descriptor_semantic_sha256;
    std::optional<std::string> identity_normalized_descriptor_semantic_sha256;
    std::optional<std::string> identity_normalized_semantic_sha256;
    bool identity_mirror_ascii_lower_match{false};
};

struct Counts final
{
    std::uint64_t candidates{0};
    std::uint64_t descriptor_parsed{0};
    std::uint64_t descriptor_rejected{0};
    std::uint64_t binding_pass{0};
    std::uint64_t binding_rejected{0};
    std::uint64_t effective_binding_pass{0};
    std::uint64_t effective_binding_rejected{0};
    std::uint64_t recovery_applied{0};
    std::uint64_t semantic_distinct{0};
    std::uint64_t effective_semantic_distinct{0};
};

struct AssetResult final
{
    std::string asset_id;
    std::string family;
    std::string structure;
    std::string candidate_set_sha256;
    std::vector<CandidateResult> candidates;
    Counts counts;
};

} // namespace tmxy::g2_asset_descriptor_diagnostics
