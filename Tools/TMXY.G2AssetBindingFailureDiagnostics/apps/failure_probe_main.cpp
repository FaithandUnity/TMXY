#include "probe_support.hpp"

#include "sha256.hpp"
#include "tmxy/animation/animation_error.hpp"
#include "tmxy/animation/package_animation_reader.hpp"
#include "tmxy/format/read_error.hpp"
#include "tmxy/static_mesh/package_static_mesh_reader.hpp"
#include "tmxy/static_mesh/static_mesh_error.hpp"
#include "tmxy/texture/legacy_texture_descriptor_reader.hpp"
#include "tmxy/texture/qtx_reader.hpp"
#include "tmxy/texture/texture_error.hpp"

#include <algorithm>
#include <exception>
#include <iostream>
#include <optional>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace
{

using tmxy::g2_asset_binding_failure::AssetEntry;
using tmxy::g2_asset_binding_failure::Candidate;
using tmxy::g2_asset_binding_failure::CandidateIndex;
using tmxy::g2_asset_binding_failure::fail;
using tmxy::g2_asset_descriptor_diagnostics::sha256_hex;

struct FailureDiagnostic final
{
    std::string candidate_id;
    std::string body_sha256;
    std::string error_schema;
    std::string error_code;
    std::optional<std::string> read_error_code;
    std::string error_context_sha256;
    std::string failure_id;
};

[[nodiscard]] std::optional<std::string>
read_error_name(const std::optional<tmxy::format::ReadErrorCode> code)
{
    if (!code.has_value()) { return std::nullopt; }
    return std::string(tmxy::format::to_string(*code));
}

[[nodiscard]] std::string failure_id(const std::string_view asset_id,
                                     const std::string_view candidate_id,
                                     const std::string_view schema,
                                     const std::string_view code,
                                     const std::optional<std::string>& read_code,
                                     const std::string_view context_sha)
{
    std::string canonical("tmxy-g2-asset-binding-failure-v1");
    const auto append = [&canonical](const std::string_view value)
    {
        canonical.push_back('\0');
        canonical.append(value);
    };
    append(asset_id);
    append(candidate_id);
    append(schema);
    append(code);
    append(read_code.has_value() ? std::string_view(*read_code) : std::string_view("none"));
    append(context_sha);
    return sha256_hex(std::string_view(canonical.data(), canonical.size()));
}

template <typename Error>
[[nodiscard]] FailureDiagnostic make_failure(const std::string_view asset_id,
                                             const Candidate& candidate,
                                             const std::span<const std::byte> body,
                                             const std::string_view schema,
                                             const std::string_view code,
                                             const Error& error)
{
    const auto context_sha = sha256_hex(error.context);
    const auto read_code = read_error_name(error.read_error_code);
    return {.candidate_id = candidate.id,
            .body_sha256 = sha256_hex(body),
            .error_schema = std::string(schema),
            .error_code = std::string(code),
            .read_error_code = read_code,
            .error_context_sha256 = context_sha,
            .failure_id = failure_id(asset_id, candidate.id, schema, code,
                                     read_code, context_sha)};
}

[[nodiscard]] FailureDiagnostic diagnose(const AssetEntry& asset,
                                         const CandidateIndex& index,
                                         const Candidate& candidate,
                                         const std::span<const std::byte> asset_bytes)
{
    const auto& package = index.packages.at(candidate.package_path).bytes;
    const auto package_bytes = std::span<const std::byte>(package.data(), package.size());
    const auto body = tmxy::g2_asset_binding_failure::candidate_body(index, candidate);
    if (asset.family == "qtx")
    {
        auto descriptor = tmxy::texture::LegacyTextureDescriptorReader{}.parse(
            body, candidate.body_offset);
        if (!descriptor.has_value()) { fail("a4_descriptor_parse_drift"); }
        auto binding = tmxy::texture::QtxReader{}.parse(descriptor.value(), asset_bytes);
        if (binding.has_value()) { fail("a4_binding_pass_requires_rerun"); }
        const auto& error = binding.error();
        return make_failure(asset.id, candidate, body, "TextureError/v1",
                            tmxy::texture::to_string(error.code), error);
    }
    if (asset.family == "sm")
    {
        auto descriptor = tmxy::static_mesh::read_static_mesh_descriptor(
            body, candidate.body_offset);
        if (!descriptor.has_value()) { fail("a4_descriptor_parse_drift"); }
        auto binding = tmxy::static_mesh::bind_static_mesh(
            package_bytes, candidate.object_name, asset_bytes);
        if (binding.has_value()) { fail("a4_binding_pass_requires_rerun"); }
        const auto& error = binding.error();
        return make_failure(asset.id, candidate, body, "StaticMeshError/v1",
                            tmxy::static_mesh::to_string(error.code), error);
    }
    if (asset.family == "anim")
    {
        auto descriptor = tmxy::animation::read_package_animation_set_descriptor(
            package_bytes, candidate.object_name);
        if (!descriptor.has_value()) { fail("a4_descriptor_parse_drift"); }
        auto binding = tmxy::animation::bind_animation_set(
            package_bytes, candidate.object_name, asset_bytes);
        if (binding.has_value()) { fail("a4_binding_pass_requires_rerun"); }
        const auto& error = binding.error();
        return make_failure(asset.id, candidate, body, "AnimationError/v1",
                            tmxy::animation::to_string(error.code), error);
    }
    fail("unsupported_asset_family");
}

void emit_string(const std::string_view value)
{
    if (std::ranges::any_of(value, [](const unsigned char byte)
        { return byte < 0x20U || byte == '\\' || byte == '"'; }))
    {
        fail("unsafe_output_token");
    }
    std::cout << '"' << value << '"';
}

void emit_candidate(const FailureDiagnostic& item)
{
    std::cout << R"({"automatic_resolution":false,"bind_result":"REJECTED","body_sha256":)";
    emit_string(item.body_sha256);
    std::cout << R"(,"candidate_id":)";
    emit_string(item.candidate_id);
    std::cout << R"(,"error_code":)";
    emit_string(item.error_code);
    std::cout << R"(,"error_context_sha256":)";
    emit_string(item.error_context_sha256);
    std::cout << R"(,"error_schema":)";
    emit_string(item.error_schema);
    std::cout << R"(,"failure_id":)";
    emit_string(item.failure_id);
    std::cout << R"(,"read_error_code":)";
    if (item.read_error_code.has_value()) { emit_string(*item.read_error_code); }
    else { std::cout << "null"; }
    std::cout << '}';
}

void inspect_asset(const AssetEntry& asset, const std::filesystem::path& client_root,
                   const CandidateIndex& index)
{
    const auto asset_bytes_vector =
        tmxy::g2_asset_binding_failure::read_file(
            tmxy::g2_asset_binding_failure::safe_join(client_root, asset.relative_path));
    if (asset_bytes_vector.size() != asset.bytes ||
        sha256_hex(asset_bytes_vector) != asset.source_sha256)
    {
        fail("asset_source_hash_drift");
    }
    const auto asset_bytes = std::span<const std::byte>(asset_bytes_vector.data(),
                                                        asset_bytes_vector.size());
    std::vector<FailureDiagnostic> diagnostics;
    for (const auto& id : asset.candidate_ids)
    {
        const auto found = index.candidates.find(id);
        if (found == index.candidates.end()) { fail("candidate_missing"); }
        diagnostics.push_back(diagnose(asset, index, found->second, asset_bytes));
    }
    std::ranges::sort(diagnostics, {}, &FailureDiagnostic::candidate_id);
    std::cout << R"({"asset_id":)";
    emit_string(asset.id);
    std::cout << R"(,"candidate_count":)" << diagnostics.size()
              << R"(,"candidate_set_sha256":)";
    emit_string(asset.candidate_set_sha256);
    std::cout << R"(,"candidates":[)";
    for (std::size_t index_value = 0; index_value < diagnostics.size(); ++index_value)
    {
        if (index_value != 0U) { std::cout << ','; }
        emit_candidate(diagnostics[index_value]);
    }
    std::cout << R"(],"family":)";
    emit_string(asset.family);
    std::cout << "}\n";
}

} // namespace

int main(const int argc, const char* const* argv)
{
    try
    {
        if (argc != 4)
        {
            std::cerr << "usage: failure_probe <client-root> <asset-tsv> <candidate-tsv>\n";
            return 2;
        }
        if (!tmxy::g2_asset_descriptor_diagnostics::sha256_self_test())
        {
            fail("sha256_self_test_failed");
        }
        auto assets = tmxy::g2_asset_binding_failure::read_asset_tsv(argv[2]);
        auto candidate_inputs = tmxy::g2_asset_binding_failure::read_candidate_tsv(argv[3]);
        if (assets.size() != 19U || candidate_inputs.size() != 24U)
        {
            fail("a7_scope_drift");
        }
        auto index = tmxy::g2_asset_binding_failure::load_candidates(argv[1], candidate_inputs);
        std::ranges::sort(assets, {}, &AssetEntry::id);
        for (const auto& asset : assets) { inspect_asset(asset, argv[1], index); }
        std::cerr << "asset_binding_failure_probe targets=19 candidate_edges=24 result=PASS_DIAGNOSTIC\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "asset_binding_failure_probe_error=" << error.what() << '\n';
        return 1;
    }
}
