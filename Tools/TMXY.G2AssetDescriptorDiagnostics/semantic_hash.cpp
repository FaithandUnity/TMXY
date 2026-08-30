#include "semantic_hash.hpp"

#include "sha256.hpp"

#include <cstdint>

namespace tmxy::g2_asset_descriptor_diagnostics
{
namespace
{

constexpr std::string_view kSemanticDomain = "tmxy-g2-asset-descriptor-semantic-v1";
constexpr std::string_view kDescriptorSemanticDomain = "tmxy-g2-asset-descriptor-body-semantic-v1";
constexpr std::string_view kNormalizedSemanticDomain =
    "tmxy-g2-asset-descriptor-ascii-lower-semantic-v1";

void append_u64_le(std::string& output, const std::uint64_t value)
{
    for (unsigned int shift = 0U; shift < 64U; shift += 8U)
    {
        output.push_back(static_cast<char>((value >> shift) & 0xFFU));
    }
}

[[nodiscard]] std::string lower_ascii(std::string value)
{
    for (auto& byte : value)
    {
        if (byte >= 'A' && byte <= 'Z')
        {
            byte = static_cast<char>(byte + ('a' - 'A'));
        }
    }
    return value;
}

[[nodiscard]] std::string hash_semantic(const std::string_view domain,
                                        const std::string_view object_name,
                                        const std::string_view signature)
{
    std::string canonical(domain);
    canonical.push_back('\0');
    append_u64_le(canonical, object_name.size());
    canonical.append(object_name);
    append_u64_le(canonical, signature.size());
    canonical.append(signature);
    return sha256_hex(std::string_view(canonical.data(), canonical.size()));
}

} // namespace

std::string semantic_sha256(const std::string_view object_name, const std::string_view signature)
{
    return hash_semantic(kSemanticDomain, object_name, signature);
}

std::string descriptor_semantic_sha256(const std::string_view signature)
{
    std::string canonical(kDescriptorSemanticDomain);
    canonical.push_back('\0');
    append_u64_le(canonical, signature.size());
    canonical.append(signature);
    return sha256_hex(std::string_view(canonical.data(), canonical.size()));
}

std::string normalized_semantic_sha256(const std::string_view object_name,
                                       const std::string_view signature)
{
    return hash_semantic(kNormalizedSemanticDomain, lower_ascii(std::string(object_name)),
                         signature);
}

} // namespace tmxy::g2_asset_descriptor_diagnostics
