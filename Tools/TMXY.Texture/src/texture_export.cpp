#include "tmxy/texture/texture_export.hpp"

#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <sstream>
#include <string>
#include <string_view>

namespace tmxy::texture
{
namespace
{

[[nodiscard]] std::string json_string(const std::string_view value)
{
    std::ostringstream output;
    output << '"';
    for (const char raw_character : value)
    {
        const auto character = static_cast<unsigned char>(raw_character);
        switch (character)
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
            if (character < 0x20U)
            {
                output << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                       << static_cast<unsigned int>(character) << std::dec;
            }
            else
            {
                output << static_cast<char>(character);
            }
        }
    }
    output << '"';
    return output.str();
}

} // namespace

std::uint64_t texture_bytes_fingerprint(const std::span<const std::byte> bytes) noexcept
{
    std::uint64_t hash = 14695981039346656037ULL;
    for (const auto byte : bytes)
    {
        hash ^= std::to_integer<std::uint8_t>(byte);
        hash *= 1099511628211ULL;
    }
    return hash;
}

std::string build_texture_json(const QtxTextureView& texture, const TextureJsonNames names)
{
    std::ostringstream output;
    output << "{\n"
           << "  \"schema_version\": 1,\n"
           << "  \"object_name\": " << json_string(names.object_name) << ",\n"
           << R"(  "format": {"value": )" << static_cast<std::int32_t>(texture.descriptor.format)
           << ", \"name\": " << json_string(to_string(texture.descriptor.format)) << "},\n"
           << "  \"width\": " << texture.descriptor.width << ",\n"
           << "  \"height\": " << texture.descriptor.height << ",\n"
           << "  \"stored_mip_count\": " << texture.descriptor.stored_mip_count << ",\n"
           << "  \"mip_count\": " << texture.descriptor.mip_count << ",\n"
           << "  \"u_clamp\": " << json_string(to_string(texture.descriptor.u_clamp)) << ",\n"
           << "  \"v_clamp\": " << json_string(to_string(texture.descriptor.v_clamp)) << ",\n"
           << "  \"alpha_encoding\": " << json_string(to_string(texture.alpha_encoding)) << ",\n"
           << "  \"alpha_coverage\": " << json_string(to_string(texture.alpha_coverage)) << ",\n"
           << "  \"payload_size\": " << texture.payload_size << ",\n"
           << "  \"unknown_property_count\": " << texture.descriptor.unknown_properties.size()
           << ",\n"
           << "  \"mips\": [\n";
    for (std::size_t index = 0; index < texture.mips.size(); ++index)
    {
        const auto& mip = texture.mips[index];
        output << "    {\"level\": " << mip.level << ", \"width\": " << mip.width
               << ", \"height\": " << mip.height << ", \"offset\": " << mip.offset
               << ", \"size\": " << mip.size << "}";
        output << (index + 1U == texture.mips.size() ? "\n" : ",\n");
    }
    output << "  ],\n"
           << R"(  "outputs": {"dds": )" << json_string(names.dds_name)
           << ", \"png\": " << json_string(names.png_name)
           << ", \"tga\": " << json_string(names.tga_name) << "}\n"
           << "}\n";
    return output.str();
}

} // namespace tmxy::texture
