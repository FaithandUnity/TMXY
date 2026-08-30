#include "qtx_recovery.hpp"

#include "descriptor_semantic_signature.hpp"
#include "semantic_hash.hpp"
#include "tmxy/texture/qtx_reader.hpp"

#include <cstddef>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace tmxy::g2_asset_descriptor_diagnostics
{
namespace
{

void apply_complete_mip_chain(const texture::TextureDescriptor& descriptor,
                              const std::span<const std::byte> payload,
                              const std::string_view object_name, CandidateResult& result)
{
    const auto inferred = texture::infer_complete_payload_mip_count(descriptor, payload);
    if (!inferred.has_value() || inferred.value() >= descriptor.mip_count)
    {
        return;
    }
    const auto recovered = texture::QtxReader{}.parse_with_mip_count_resolution(
        descriptor, payload,
        {.effective_mip_count = inferred.value(),
         .basis = texture::MipCountBasis::payload_complete_chain_contract});
    if (!recovered.has_value())
    {
        throw std::runtime_error("recovery_plan_qtx_inference_drift");
    }
    auto effective_descriptor = descriptor;
    effective_descriptor.mip_count = inferred.value();
    effective_descriptor.stored_mip_count = inferred.value() == 1U ? 0U : inferred.value();
    const auto effective = asset_inventory::semantic_signature(effective_descriptor);
    result.effective_semantic_sha256 =
        semantic_sha256(object_name, std::string_view(effective.data(), effective.size()));
    result.effective_binding_passed = true;
    result.recovery_applied = true;
}

void apply_declared_mip_payload_prefix(const texture::TextureDescriptor& descriptor,
                                       const std::span<const std::byte> payload,
                                       CandidateResult& result)
{
    const auto recovered =
        texture::QtxReader{}.parse_with_declared_mip_payload_prefix(descriptor, payload);
    if (!recovered.has_value())
    {
        throw std::runtime_error("recovery_plan_qtx_payload_prefix_drift");
    }
    const auto& view = recovered.value();
    const bool complete_declared_prefix =
        !view.mips.empty() && view.mips.size() == descriptor.mip_count &&
        view.mips.back().offset <= view.consumed_payload_bytes &&
        view.mips.back().size == view.consumed_payload_bytes - view.mips.back().offset;
    if (view.payload_size != payload.size() || view.input_payload_bytes != payload.size() ||
        view.consumed_payload_bytes >= view.input_payload_bytes ||
        view.ignored_payload_bytes != view.input_payload_bytes - view.consumed_payload_bytes ||
        view.payload_extent_basis !=
            texture::PayloadExtentBasis::declared_mip_payload_prefix_contract ||
        view.mip_count_basis != texture::MipCountBasis::package_descriptor ||
        view.effective_mip_count != descriptor.mip_count ||
        view.descriptor.mip_count != descriptor.mip_count || !complete_declared_prefix ||
        view.descriptor.stored_mip_count != descriptor.stored_mip_count ||
        view.descriptor.stored_mip_count != view.descriptor.mip_count ||
        !result.semantic_sha256.has_value())
    {
        throw std::runtime_error("recovery_plan_qtx_payload_prefix_view_drift");
    }
    result.effective_semantic_sha256 = result.semantic_sha256;
    result.effective_binding_passed = true;
    result.recovery_applied = true;
}

} // namespace

void apply_qtx_recovery(const texture::TextureDescriptor& descriptor,
                        const std::span<const std::byte> payload,
                        const std::string_view object_name, const RecoveryDirective& directive,
                        CandidateResult& result)
{
    if (directive.recovery_kind == "qtx_complete_mip_chain")
    {
        apply_complete_mip_chain(descriptor, payload, object_name, result);
        return;
    }
    if (directive.recovery_kind == "qtx_declared_mip_payload_prefix")
    {
        apply_declared_mip_payload_prefix(descriptor, payload, result);
        return;
    }
    throw std::runtime_error("recovery_plan_qtx_kind_drift");
}

bool qtx_recovery_self_test() noexcept
{
    try
    {
        const texture::TextureDescriptor descriptor{.format = texture::TextureFormat::dxt1,
                                                    .u_clamp = texture::ClampMode::wrap,
                                                    .v_clamp = texture::ClampMode::wrap,
                                                    .width = 8U,
                                                    .height = 8U,
                                                    .stored_mip_count = 2U,
                                                    .mip_count = 2U,
                                                    .unknown_properties = {}};
        const std::vector<std::byte> payload(48U, std::byte{0});
        if (texture::QtxReader{}.parse(descriptor, payload).has_value())
        {
            return false;
        }
        RecoveryDirective directive;
        directive.recovery_kind = "qtx_declared_mip_payload_prefix";
        CandidateResult result;
        result.semantic_sha256 = std::string(64U, 'a');
        apply_qtx_recovery(descriptor, payload, "self-test.texture", directive, result);
        return result.effective_binding_passed && result.recovery_applied &&
               result.effective_semantic_sha256 == result.semantic_sha256;
    }
    catch (...)
    {
        return false;
    }
}

} // namespace tmxy::g2_asset_descriptor_diagnostics
