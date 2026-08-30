#include "descriptor_semantic_signature.hpp"
#include "probe_support.hpp"
#include "semantic_hash.hpp"
#include "sha256.hpp"

#include "tmxy/texture/package_texture_reader.hpp"
#include "tmxy/texture/qtx_reader.hpp"
#include "tmxy/texture/texture_error.hpp"
#include "tmxy/texture/texture_export.hpp"

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
    std::string input_payload_sha256;
    std::string consumed_payload_sha256;
    std::string ignored_tail_sha256;
    std::string decoded_mip_zero_sha256;
    std::string dds_sha256;
    std::string dds_payload_sha256;
    std::string format;
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint32_t stored_mip_count{0};
    std::uint32_t declared_mip_count{0};
    std::uint32_t effective_mip_count{0};
    std::uint32_t payload_boundary_mip_count{0};
    std::uint32_t maximum_natural_mip_count{0};
    std::uint64_t input_payload_bytes{0};
    std::uint64_t consumed_payload_bytes{0};
    std::uint64_t ignored_payload_bytes{0};
    std::uint64_t decoded_mip_zero_bytes{0};
    std::uint64_t dds_bytes{0};
};

void append_u64_le(std::string& output, const std::uint64_t value)
{
    for (unsigned int shift = 0U; shift < 64U; shift += 8U)
    {
        output.push_back(static_cast<char>((value >> shift) & 0xFFU));
    }
}

[[nodiscard]] std::uint32_t read_u32_le(const std::span<const std::byte> bytes,
                                        const std::size_t offset)
{
    if (offset + 4U > bytes.size()) { fail("dds_header_truncated"); }
    return std::to_integer<std::uint32_t>(bytes[offset]) |
           (std::to_integer<std::uint32_t>(bytes[offset + 1U]) << 8U) |
           (std::to_integer<std::uint32_t>(bytes[offset + 2U]) << 16U) |
           (std::to_integer<std::uint32_t>(bytes[offset + 3U]) << 24U);
}

[[nodiscard]] std::uint32_t maximum_natural_mips(std::uint32_t width,
                                                  std::uint32_t height) noexcept
{
    std::uint32_t result = 1U;
    while (width > 1U || height > 1U)
    {
        width = std::max(1U, width / 2U);
        height = std::max(1U, height / 2U);
        ++result;
    }
    return result;
}

[[nodiscard]] std::string prefix_semantic(const AssetEntry& asset,
                                          const CandidateProof& proof)
{
    std::string canonical("tmxy-g2-qtx-declared-mip-payload-prefix-v1");
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
    append(proof.consumed_payload_sha256);
    append(proof.ignored_tail_sha256);
    append(proof.decoded_mip_zero_sha256);
    append(proof.dds_sha256);
    append("declared_mip_payload_prefix_contract");
    append_u64_le(canonical, proof.payload_boundary_mip_count);
    append_u64_le(canonical, proof.maximum_natural_mip_count);
    append_u64_le(canonical, proof.input_payload_bytes);
    append_u64_le(canonical, proof.consumed_payload_bytes);
    append_u64_le(canonical, proof.ignored_payload_bytes);
    return sha256_hex(std::string_view(canonical.data(), canonical.size()));
}

[[nodiscard]] CandidateProof inspect_candidate(const AssetEntry& asset,
                                               const CandidateIndex& index,
                                               const Candidate& candidate,
                                               const std::span<const std::byte> payload)
{
    const auto& package = index.packages.at(candidate.package_path).bytes;
    const auto package_bytes = std::span<const std::byte>(package.data(), package.size());
    const auto body = tmxy::g2_asset_binding_failure::candidate_body(index, candidate);
    auto parsed = tmxy::texture::read_package_texture_descriptor(package_bytes, candidate.object_name);
    if (!parsed.has_value()) { fail("texture_descriptor_parse_drift"); }
    const auto signature_value =
        tmxy::asset_inventory::semantic_signature(parsed.value().descriptor);
    const auto signature = std::string_view(signature_value.data(), signature_value.size());
    const auto& descriptor = parsed.value().descriptor;

    auto strict = tmxy::texture::QtxReader{}.parse(descriptor, payload);
    if (strict.has_value() ||
        strict.error().code != tmxy::texture::TextureErrorCode::payload_size_mismatch)
    {
        fail("strict_payload_size_mismatch_drift");
    }
    auto boundary = tmxy::texture::infer_complete_payload_mip_count(descriptor, payload);
    if (!boundary.has_value() || boundary.value() <= descriptor.mip_count)
    {
        fail("full_payload_boundary_drift");
    }
    auto explicit_prefix =
        tmxy::texture::QtxReader{}.parse_with_declared_mip_payload_prefix(descriptor, payload);
    if (!explicit_prefix.has_value()) { fail("declared_mip_prefix_binding_rejected"); }
    const auto& texture = explicit_prefix.value();
    if (texture.payload_extent_basis !=
            tmxy::texture::PayloadExtentBasis::declared_mip_payload_prefix_contract ||
        texture.mip_count_basis != tmxy::texture::MipCountBasis::package_descriptor ||
        texture.descriptor.stored_mip_count != 1U || texture.descriptor.mip_count != 1U ||
        texture.effective_mip_count != 1U || texture.input_payload_bytes != payload.size() ||
        texture.consumed_payload_bytes == 0U || texture.ignored_payload_bytes == 0U ||
        texture.consumed_payload_bytes + texture.ignored_payload_bytes != payload.size())
    {
        fail("declared_mip_prefix_relation_drift");
    }
    const auto consumed = payload.first(static_cast<std::size_t>(texture.consumed_payload_bytes));
    const auto ignored = payload.subspan(static_cast<std::size_t>(texture.consumed_payload_bytes));
    auto strict_prefix = tmxy::texture::QtxReader{}.parse(descriptor, consumed);
    if (!strict_prefix.has_value()) { fail("strict_prefix_parse_rejected"); }
    auto decoded_explicit = tmxy::texture::decode_mip_zero_rgba8(texture, payload);
    auto decoded_strict =
        tmxy::texture::decode_mip_zero_rgba8(strict_prefix.value(), consumed);
    if (!decoded_explicit.has_value() || !decoded_strict.has_value() ||
        decoded_explicit.value() != decoded_strict.value())
    {
        fail("decoded_mip_zero_prefix_mismatch");
    }
    auto dds_result = tmxy::texture::build_dds(texture, payload);
    if (!dds_result.has_value()) { fail("dds_prefix_export_rejected"); }
    const auto& dds = dds_result.value();
    const auto dds_span = std::span<const std::byte>(dds.data(), dds.size());
    constexpr std::size_t kDdsHeaderBytes = 128U;
    if (dds.size() != kDdsHeaderBytes + consumed.size() ||
        read_u32_le(dds_span, 28U) != 1U ||
        !std::ranges::equal(dds_span.subspan(kDdsHeaderBytes), consumed))
    {
        fail("dds_contains_non_prefix_payload");
    }

    CandidateProof proof{
        .candidate_id = candidate.id,
        .package_sha256 = sha256_hex(package_bytes),
        .body_sha256 = sha256_hex(body),
        .descriptor_semantic_sha256 = descriptor_semantic_sha256(signature),
        .strict_semantic_sha256 = semantic_sha256(candidate.object_name, signature),
        .prefix_semantic_sha256 = {},
        .input_payload_sha256 = sha256_hex(payload),
        .consumed_payload_sha256 = sha256_hex(consumed),
        .ignored_tail_sha256 = sha256_hex(ignored),
        .decoded_mip_zero_sha256 = sha256_hex(decoded_explicit.value()),
        .dds_sha256 = sha256_hex(dds_span),
        .dds_payload_sha256 = sha256_hex(dds_span.subspan(kDdsHeaderBytes)),
        .format = tmxy::texture::to_string(descriptor.format),
        .width = descriptor.width,
        .height = descriptor.height,
        .stored_mip_count = descriptor.stored_mip_count,
        .declared_mip_count = descriptor.mip_count,
        .effective_mip_count = texture.effective_mip_count,
        .payload_boundary_mip_count = boundary.value(),
        .maximum_natural_mip_count = maximum_natural_mips(descriptor.width, descriptor.height),
        .input_payload_bytes = payload.size(),
        .consumed_payload_bytes = texture.consumed_payload_bytes,
        .ignored_payload_bytes = texture.ignored_payload_bytes,
        .decoded_mip_zero_bytes = decoded_explicit.value().size(),
        .dds_bytes = dds.size(),
    };
    if (proof.consumed_payload_sha256 != proof.dds_payload_sha256)
    {
        fail("dds_payload_hash_mismatch");
    }
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
    std::cout << R"({"adapter_applied":false,"body_sha256":)"; emit_string(item.body_sha256);
    std::cout << R"(,"candidate_id":)"; emit_string(item.candidate_id);
    std::cout << R"(,"consumed_payload_bytes":)" << item.consumed_payload_bytes;
    std::cout << R"(,"consumed_payload_sha256":)"; emit_string(item.consumed_payload_sha256);
    std::cout << R"(,"content_disposition":"NONE","dds_bytes":)" << item.dds_bytes;
    std::cout << R"(,"dds_declared_mip_count":1,"dds_header_bytes":128,"dds_payload_bytes":)"
              << item.consumed_payload_bytes;
    std::cout << R"(,"dds_payload_prefix_only":true,"dds_payload_sha256":)";
    emit_string(item.dds_payload_sha256);
    std::cout << R"(,"dds_sha256":)"; emit_string(item.dds_sha256);
    std::cout << R"(,"declared_mip_count":)" << item.declared_mip_count;
    std::cout << R"(,"decoded_mip_zero_bytes":)" << item.decoded_mip_zero_bytes;
    std::cout << R"(,"decoded_mip_zero_sha256":)"; emit_string(item.decoded_mip_zero_sha256);
    std::cout << R"(,"descriptor_semantic_sha256":)"; emit_string(item.descriptor_semantic_sha256);
    std::cout << R"(,"effective_mip_count":)" << item.effective_mip_count;
    std::cout << R"(,"explicit_prefix_binding":"PASS","format":)"; emit_string(item.format);
    std::cout << R"(,"height":)" << item.height;
    std::cout << R"(,"ignored_payload_bytes":)" << item.ignored_payload_bytes;
    std::cout << R"(,"ignored_tail_excluded_from_dds":true,"ignored_tail_sha256":)";
    emit_string(item.ignored_tail_sha256);
    std::cout << R"(,"input_payload_bytes":)" << item.input_payload_bytes;
    std::cout << R"(,"input_payload_sha256":)"; emit_string(item.input_payload_sha256);
    std::cout << R"(,"maximum_natural_mip_count":)" << item.maximum_natural_mip_count;
    std::cout << R"(,"package_sha256":)"; emit_string(item.package_sha256);
    std::cout << R"(,"payload_boundary_mip_count":)" << item.payload_boundary_mip_count;
    std::cout << R"(,"payload_extent_basis":"declared_mip_payload_prefix_contract","prefix_semantic_sha256":)";
    emit_string(item.prefix_semantic_sha256);
    std::cout << R"(,"recovery_applied":false,"stored_mip_count":)" << item.stored_mip_count;
    std::cout << R"(,"strict_binding":"REJECTED","strict_error_code":"payload_size_mismatch","strict_prefix_binding":"PASS","strict_semantic_sha256":)";
    emit_string(item.strict_semantic_sha256);
    std::cout << R"(,"width":)" << item.width << '}';
}

[[nodiscard]] CandidateProof inspect_asset(const AssetEntry& asset,
                                           const std::filesystem::path& client_root,
                                           const CandidateIndex& index)
{
    auto source = tmxy::g2_asset_binding_failure::read_file(
        tmxy::g2_asset_binding_failure::safe_join(client_root, asset.relative_path));
    if (source.size() != asset.bytes || sha256_hex(source) != asset.source_sha256 ||
        asset.candidate_ids.size() != 1U)
    {
        fail("asset_source_or_candidate_scope_drift");
    }
    const auto found = index.candidates.find(asset.candidate_ids.front());
    if (found == index.candidates.end()) { fail("candidate_missing"); }
    auto proof = inspect_candidate(asset, index, found->second,
        std::span<const std::byte>(source.data(), source.size()));
    std::cout << R"({"a13_resolution_change":false,"asset_id":)"; emit_string(asset.id);
    std::cout << R"(,"authority_state_changed":false,"automatic_resolution":false,"basis":"declared_mip_payload_prefix_contract","candidate":)";
    emit_candidate(proof);
    std::cout << R"(,"candidate_count":1,"candidate_selected":false,"candidate_set_sha256":)";
    emit_string(asset.candidate_set_sha256);
    std::cout << R"(,"family":"qtx","recovery_kind":"qtx_declared_mip_payload_prefix","source_strict_resolution":"UNRESOLVED"})"
              << '\n';
    return proof;
}

} // namespace

int main(const int argc, const char* const* argv)
{
    try
    {
        if (argc != 4)
        {
            std::cerr << "usage: qtx_declared_mip_prefix_probe <client-root> <asset-tsv> <candidate-tsv>\n";
            return 2;
        }
        if (!tmxy::g2_asset_descriptor_diagnostics::sha256_self_test() ||
            !tmxy::asset_inventory::semantic_signature_self_test())
        {
            fail("startup_self_test_failed");
        }
        auto assets = tmxy::g2_asset_binding_failure::read_asset_tsv(argv[2]);
        auto candidates = tmxy::g2_asset_binding_failure::read_candidate_tsv(argv[3]);
        if (assets.size() != 6U || candidates.size() != 6U ||
            !std::ranges::all_of(assets, [](const AssetEntry& item) { return item.family == "qtx"; }))
        {
            fail("a13_scope_drift");
        }
        auto index = tmxy::g2_asset_binding_failure::load_candidates(argv[1], candidates);
        std::uint32_t dxt1 = 0U;
        std::uint32_t dxt5 = 0U;
        for (const auto& asset : assets)
        {
            const auto proof = inspect_asset(asset, argv[1], index);
            if (proof.format == "dxt1" && proof.width == 512U && proof.height == 512U &&
                proof.payload_boundary_mip_count == 10U && proof.maximum_natural_mip_count == 10U &&
                proof.input_payload_bytes == 174776U && proof.consumed_payload_bytes == 131072U &&
                proof.ignored_payload_bytes == 43704U)
            {
                ++dxt1;
            }
            else if (proof.format == "dxt5" && proof.width == 256U && proof.height == 256U &&
                     proof.payload_boundary_mip_count == 7U && proof.maximum_natural_mip_count == 9U &&
                     proof.input_payload_bytes == 87376U && proof.consumed_payload_bytes == 65536U &&
                     proof.ignored_payload_bytes == 21840U)
            {
                ++dxt5;
            }
            else
            {
                fail("a13_payload_pattern_drift");
            }
        }
        if (dxt1 != 3U || dxt5 != 3U) { fail("a13_pattern_count_drift"); }
        std::cerr << "qtx_declared_mip_prefix_probe targets=6 candidate_edges=6 result=PASS_DIAGNOSTIC\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "qtx_declared_mip_prefix_probe_error=" << error.what() << '\n';
        return 1;
    }
}
