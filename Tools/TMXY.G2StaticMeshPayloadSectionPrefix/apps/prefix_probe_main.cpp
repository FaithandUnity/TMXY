#include "descriptor_semantic_signature.hpp"
#include "probe_support.hpp"
#include "semantic_hash.hpp"
#include "sha256.hpp"

#include "tmxy/static_mesh/package_static_mesh_reader.hpp"
#include "tmxy/static_mesh/sm_reader.hpp"
#include "tmxy/static_mesh/static_mesh_error.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <ranges>
#include <set>
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
using tmxy::g2_asset_descriptor_diagnostics::descriptor_semantic_sha256;
using tmxy::g2_asset_descriptor_diagnostics::semantic_sha256;
using tmxy::g2_asset_descriptor_diagnostics::sha256_hex;

struct CandidateProof final
{
    std::string candidate_id;
    std::string package_sha256;
    std::string body_sha256;
    std::string descriptor_semantic_sha256;
    std::string strict_semantic_sha256;
    std::string prefix_semantic_sha256;
    std::uint64_t declared_material_slots{0};
    std::uint64_t payload_sections{0};
    std::uint64_t nonempty_payload_sections{0};
    std::uint64_t ignored_trailing_material_slots{0};
};

void append_u64_le(std::string& output, const std::uint64_t value)
{
    for (unsigned int shift = 0U; shift < 64U; shift += 8U)
    {
        output.push_back(static_cast<char>((value >> shift) & 0xFFU));
    }
}

[[nodiscard]] std::string prefix_semantic(const AssetEntry& asset,
                                          const CandidateProof& proof)
{
    std::string canonical("tmxy-g2-static-mesh-prefix-binding-v1");
    const auto append = [&canonical](const std::string_view value)
    {
        canonical.push_back('\0');
        append_u64_le(canonical, value.size());
        canonical.append(value);
    };
    append(asset.source_sha256);
    append(proof.body_sha256);
    append(proof.descriptor_semantic_sha256);
    append(proof.strict_semantic_sha256);
    append("payload_section_prefix_contract");
    append_u64_le(canonical, proof.declared_material_slots);
    append_u64_le(canonical, proof.payload_sections);
    append_u64_le(canonical, proof.nonempty_payload_sections);
    append_u64_le(canonical, proof.ignored_trailing_material_slots);
    return sha256_hex(std::string_view(canonical.data(), canonical.size()));
}

[[nodiscard]] CandidateProof inspect_candidate(const AssetEntry& asset,
                                               const CandidateIndex& index,
                                               const Candidate& candidate,
                                               const std::span<const std::byte> asset_bytes)
{
    const auto& package = index.packages.at(candidate.package_path).bytes;
    const auto package_bytes = std::span<const std::byte>(package.data(), package.size());
    const auto body = tmxy::g2_asset_binding_failure::candidate_body(index, candidate);
    auto descriptor = tmxy::static_mesh::read_package_static_mesh_descriptor(
        package_bytes, candidate.object_name);
    if (!descriptor.has_value()) { fail("static_mesh_descriptor_parse_drift"); }
    const auto signature_value =
        tmxy::asset_inventory::semantic_signature(descriptor.value().descriptor);
    const auto signature = std::string_view(signature_value.data(), signature_value.size());

    auto strict = tmxy::static_mesh::bind_static_mesh(
        package_bytes, candidate.object_name, asset_bytes);
    if (strict.has_value() ||
        strict.error().code != tmxy::static_mesh::StaticMeshErrorCode::material_slot_mismatch)
    {
        fail("strict_material_slot_mismatch_drift");
    }
    auto mesh = tmxy::static_mesh::SmReader{}.parse(asset_bytes);
    if (!mesh.has_value()) { fail("static_mesh_payload_parse_drift"); }
    const auto nonempty = static_cast<std::uint64_t>(std::ranges::count_if(
        mesh.value().sections, [](const tmxy::static_mesh::MeshSection& section)
        { return section.triangle_count > 0U; }));

    auto prefix = tmxy::static_mesh::bind_static_mesh_with_payload_section_prefix(
        package_bytes, candidate.object_name, asset_bytes);
    if (!prefix.has_value()) { fail("prefix_contract_binding_rejected"); }
    const auto& resolution = prefix.value().material_slot_resolution;
    if (resolution.basis != tmxy::static_mesh::MaterialSlotBasis::payload_section_prefix_contract ||
        resolution.declared_material_slot_count != 2U ||
        resolution.effective_material_slot_count != 1U ||
        resolution.ignored_material_slot_count != 1U || mesh.value().sections.size() != 1U ||
        nonempty != 1U)
    {
        fail("prefix_contract_relation_drift");
    }

    CandidateProof proof{
        .candidate_id = candidate.id,
        .package_sha256 = sha256_hex(package_bytes),
        .body_sha256 = sha256_hex(body),
        .descriptor_semantic_sha256 = descriptor_semantic_sha256(signature),
        .strict_semantic_sha256 = semantic_sha256(candidate.object_name, signature),
        .prefix_semantic_sha256 = {},
        .declared_material_slots = resolution.declared_material_slot_count,
        .payload_sections = resolution.effective_material_slot_count,
        .nonempty_payload_sections = nonempty,
        .ignored_trailing_material_slots = resolution.ignored_material_slot_count,
    };
    proof.prefix_semantic_sha256 = prefix_semantic(asset, proof);
    return proof;
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

void emit_candidate(const CandidateProof& item)
{
    std::cout << R"({"adapter_applied":false,"body_sha256":)";
    emit_string(item.body_sha256);
    std::cout << R"(,"candidate_id":)"; emit_string(item.candidate_id);
    std::cout << R"(,"content_disposition":"NONE","declared_material_slots":)"
              << item.declared_material_slots;
    std::cout << R"(,"descriptor_semantic_sha256":)";
    emit_string(item.descriptor_semantic_sha256);
    std::cout << R"(,"ignored_trailing_material_slots":)"
              << item.ignored_trailing_material_slots;
    std::cout << R"(,"nonempty_payload_sections":)" << item.nonempty_payload_sections;
    std::cout << R"(,"package_sha256":)"; emit_string(item.package_sha256);
    std::cout << R"(,"payload_sections":)" << item.payload_sections;
    std::cout << R"(,"prefix_binding":"PASS","prefix_semantic_sha256":)";
    emit_string(item.prefix_semantic_sha256);
    std::cout << R"(,"recovery_applied":false,"slot_basis":"payload_section_prefix_contract","strict_binding":"REJECTED","strict_error_code":"material_slot_mismatch","strict_semantic_sha256":)";
    emit_string(item.strict_semantic_sha256);
    std::cout << '}';
}

void inspect_asset(const AssetEntry& asset, const std::filesystem::path& client_root,
                   const CandidateIndex& index)
{
    auto source = tmxy::g2_asset_binding_failure::read_file(
        tmxy::g2_asset_binding_failure::safe_join(client_root, asset.relative_path));
    if (source.size() != asset.bytes || sha256_hex(source) != asset.source_sha256)
    {
        fail("asset_source_hash_drift");
    }
    const auto bytes = std::span<const std::byte>(source.data(), source.size());
    std::vector<CandidateProof> candidates;
    for (const auto& identity : asset.candidate_ids)
    {
        const auto found = index.candidates.find(identity);
        if (found == index.candidates.end()) { fail("candidate_missing"); }
        candidates.push_back(inspect_candidate(asset, index, found->second, bytes));
    }
    std::ranges::sort(candidates, {}, &CandidateProof::candidate_id);
    std::cout << R"({"asset_id":)"; emit_string(asset.id);
    std::cout << R"(,"automatic_resolution":false,"authority_state_changed":false,"basis":"payload_section_prefix_contract","candidate_count":2,"candidate_selected":false,"candidate_set_sha256":)";
    emit_string(asset.candidate_set_sha256);
    std::cout << R"(,"candidates":[)";
    for (std::size_t position = 0; position < candidates.size(); ++position)
    {
        if (position != 0U) { std::cout << ','; }
        emit_candidate(candidates[position]);
    }
    std::cout << R"(],"effective_resolution":"UNRESOLVED","family":"sm","recovery_kind":"sm_payload_section_prefix"})"
              << '\n';
}

} // namespace

int main(const int argc, const char* const* argv)
{
    try
    {
        if (argc != 4)
        {
            std::cerr << "usage: prefix_probe <client-root> <asset-tsv> <candidate-tsv>\n";
            return 2;
        }
        if (!tmxy::g2_asset_descriptor_diagnostics::sha256_self_test() ||
            !tmxy::asset_inventory::semantic_signature_self_test())
        {
            fail("startup_self_test_failed");
        }
        auto assets = tmxy::g2_asset_binding_failure::read_asset_tsv(argv[2]);
        auto candidates = tmxy::g2_asset_binding_failure::read_candidate_tsv(argv[3]);
        if (assets.size() != 1U || candidates.size() != 2U || assets[0].family != "sm" ||
            std::set<std::string>{candidates[0].package_path, candidates[1].package_path}.size() != 2U)
        {
            fail("a12_scope_drift");
        }
        auto index = tmxy::g2_asset_binding_failure::load_candidates(argv[1], candidates);
        inspect_asset(assets[0], argv[1], index);
        std::cerr << "static_mesh_prefix_probe targets=1 candidate_edges=2 result=PASS_DIAGNOSTIC\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "static_mesh_prefix_probe_error=" << error.what() << '\n';
        return 1;
    }
}
