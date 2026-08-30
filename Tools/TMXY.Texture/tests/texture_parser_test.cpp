#include "tmxy/texture/legacy_texture_descriptor_reader.hpp"
#include "tmxy/texture/qtx_reader.hpp"
#include "tmxy/texture/texture_export.hpp"

#include <cstddef>
#include <cstdint>
#include <iostream>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace
{

class TestContext final
{
  public:
    void expect(const bool condition, const std::string_view message)
    {
        ++checks_;
        if (!condition)
        {
            ++failures_;
            std::cerr << "FAIL: " << message << '\n';
        }
    }

    [[nodiscard]] int result() const
    {
        std::cout << "checks=" << checks_ << " failures=" << failures_ << '\n';
        return failures_ == 0 ? 0 : 1;
    }

  private:
    int checks_{0};
    int failures_{0};
};

void append_u16(std::vector<std::byte>& bytes, const std::uint16_t value)
{
    bytes.push_back(static_cast<std::byte>(value & 0xFFU));
    bytes.push_back(static_cast<std::byte>((value >> 8U) & 0xFFU));
}

void append_i32(std::vector<std::byte>& bytes, const std::int32_t value)
{
    const auto converted = static_cast<std::uint32_t>(value);
    for (unsigned int shift = 0; shift < 32U; shift += 8U)
    {
        bytes.push_back(static_cast<std::byte>((converted >> shift) & 0xFFU));
    }
}

void append_property(std::vector<std::byte>& body, const std::string_view name,
                     const std::span<const std::byte> value)
{
    append_u16(body, static_cast<std::uint16_t>(name.size()));
    for (const char character : name)
    {
        body.push_back(static_cast<std::byte>(character));
    }
    append_u16(body, static_cast<std::uint16_t>(value.size()));
    body.insert(body.end(), value.begin(), value.end());
}

void append_i32_property(std::vector<std::byte>& body, const std::string_view name,
                         const std::int32_t value)
{
    std::vector<std::byte> encoded;
    append_i32(encoded, value);
    append_property(body, name, encoded);
}

[[nodiscard]] std::vector<std::byte> make_descriptor(const tmxy::texture::TextureFormat format,
                                                     const std::int32_t width,
                                                     const std::int32_t height,
                                                     const std::int32_t mips,
                                                     const bool include_format = true)
{
    std::vector<std::byte> body;
    append_u16(body, include_format ? 4U : 3U);
    if (include_format)
    {
        append_i32_property(body, "format", static_cast<std::int32_t>(format));
    }
    append_i32_property(body, "uSize", width);
    append_i32_property(body, "vSize", height);
    append_i32_property(body, "mipLevel", mips);
    return body;
}

[[nodiscard]] tmxy::texture::TextureDescriptor parse_descriptor(TestContext& test,
                                                                const std::vector<std::byte>& body,
                                                                const std::string_view message)
{
    auto parsed = tmxy::texture::LegacyTextureDescriptorReader{}.parse(body, 100U);
    test.expect(parsed.has_value(), message);
    return parsed.has_value() ? parsed.value() : tmxy::texture::TextureDescriptor{};
}

void test_descriptor(TestContext& test)
{
    auto body = make_descriptor(tmxy::texture::TextureFormat::dxt1, 8, 8, 1);
    auto descriptor = parse_descriptor(test, body, "valid descriptor parses");
    test.expect(descriptor.format == tmxy::texture::TextureFormat::dxt1, "format property decoded");
    test.expect(descriptor.width == 8U && descriptor.height == 8U && descriptor.mip_count == 1U,
                "dimensions and mip decoded");

    auto defaults = make_descriptor(tmxy::texture::TextureFormat::rgba8, 2, 1, 0, false);
    auto default_descriptor = parse_descriptor(test, defaults, "omitted defaults parse");
    test.expect(default_descriptor.format == tmxy::texture::TextureFormat::rgba8,
                "omitted format defaults to rgba8");
    test.expect(default_descriptor.stored_mip_count == 0U && default_descriptor.mip_count == 1U,
                "stored mip zero canonicalizes to one");

    std::vector<std::byte> unknown;
    append_u16(unknown, 4U);
    append_i32_property(unknown, "uSize", 4);
    append_i32_property(unknown, "vSize", 4);
    append_i32_property(unknown, "mipLevel", 1);
    const std::vector<std::byte> future{std::byte{0xAA}, std::byte{0xBB}};
    append_property(unknown, "future", future);
    auto with_unknown = parse_descriptor(test, unknown, "unknown property preserved");
    test.expect(with_unknown.unknown_properties.size() == 1U &&
                    with_unknown.unknown_properties[0].value == future,
                "unknown property value retained");

    std::vector<std::byte> duplicate;
    append_u16(duplicate, 4U);
    append_i32_property(duplicate, "uSize", 4);
    append_i32_property(duplicate, "uSize", 4);
    append_i32_property(duplicate, "vSize", 4);
    append_i32_property(duplicate, "mipLevel", 1);
    const auto duplicate_result = tmxy::texture::LegacyTextureDescriptorReader{}.parse(duplicate);
    test.expect(!duplicate_result.has_value() &&
                    duplicate_result.error().code ==
                        tmxy::texture::TextureErrorCode::duplicate_property,
                "duplicate known property rejected");

    auto invalid_format = make_descriptor(tmxy::texture::TextureFormat::rgba8, 4, 4, 1);
    invalid_format[12] = std::byte{99};
    const auto format_result = tmxy::texture::LegacyTextureDescriptorReader{}.parse(invalid_format);
    test.expect(!format_result.has_value() &&
                    format_result.error().code == tmxy::texture::TextureErrorCode::invalid_format,
                "invalid format rejected");

    auto invalid_mips = make_descriptor(tmxy::texture::TextureFormat::dxt1, 4, 4, 4);
    const auto mip_result = tmxy::texture::LegacyTextureDescriptorReader{}.parse(invalid_mips);
    test.expect(!mip_result.has_value() &&
                    mip_result.error().code == tmxy::texture::TextureErrorCode::invalid_mip_count,
                "impossible mip chain rejected");

    auto trailing = body;
    trailing.push_back(std::byte{0});
    const auto trailing_result = tmxy::texture::LegacyTextureDescriptorReader{}.parse(trailing);
    test.expect(!trailing_result.has_value() &&
                    trailing_result.error().code ==
                        tmxy::texture::TextureErrorCode::trailing_descriptor_bytes,
                "trailing descriptor bytes rejected");

    auto truncated = body;
    truncated.pop_back();
    const auto truncated_result = tmxy::texture::LegacyTextureDescriptorReader{}.parse(truncated);
    test.expect(!truncated_result.has_value() &&
                    truncated_result.error().code == tmxy::texture::TextureErrorCode::read_failure,
                "truncated descriptor rejected");
}

void test_rgba_outputs(TestContext& test)
{
    const auto body = make_descriptor(tmxy::texture::TextureFormat::rgba8, 2, 1, 1, false);
    auto descriptor = parse_descriptor(test, body, "rgba descriptor parses");
    const std::vector<std::byte> payload{std::byte{10},  std::byte{20}, std::byte{30},
                                         std::byte{255}, std::byte{40}, std::byte{50},
                                         std::byte{60},  std::byte{128}};
    auto texture = tmxy::texture::QtxReader{}.parse(descriptor, payload);
    test.expect(texture.has_value(), "rgba payload parses");
    test.expect(texture.has_value() && texture.value().input_payload_bytes == payload.size() &&
                    texture.value().consumed_payload_bytes == payload.size() &&
                    texture.value().ignored_payload_bytes == 0U &&
                    texture.value().payload_extent_basis ==
                        tmxy::texture::PayloadExtentBasis::complete_input_payload,
                "strict QTX view consumes the complete input payload");
    if (!texture.has_value())
    {
        return;
    }
    test.expect(texture.value().alpha_coverage == tmxy::texture::AlphaCoverage::translucent,
                "rgba alpha coverage detected");
    auto rgba = tmxy::texture::decode_mip_zero_rgba8(texture.value(), payload);
    test.expect(rgba.has_value() && rgba.value()[0] == std::byte{30} &&
                    rgba.value()[1] == std::byte{20} && rgba.value()[2] == std::byte{10},
                "bgra payload normalized to rgba");

    auto dds = tmxy::texture::build_dds(texture.value(), payload);
    auto png = tmxy::texture::build_png(texture.value(), payload);
    auto tga = tmxy::texture::build_tga(texture.value(), payload);
    test.expect(dds.has_value() && dds.value().size() == 136U && dds.value()[0] == std::byte{'D'} &&
                    dds.value()[128] == payload[0],
                "dds header and original payload emitted");
    test.expect(png.has_value() && png.value().size() > 60U && png.value()[0] == std::byte{0x89} &&
                    png.value()[1] == std::byte{'P'} && png.value()[16] == std::byte{0} &&
                    png.value()[17] == std::byte{0} && png.value()[18] == std::byte{0} &&
                    png.value()[19] == std::byte{2},
                "png signature and width emitted");
    test.expect(tga.has_value() && tga.value().size() == 26U &&
                    tga.value()[17] == std::byte{0x28} && tga.value()[18] == payload[0],
                "tga header and bgra pixel emitted");
    auto second_png = tmxy::texture::build_png(texture.value(), payload);
    test.expect(second_png.has_value() && second_png.value() == png.value(),
                "png output deterministic");
    const auto json = tmxy::texture::build_texture_json(
        texture.value(),
        {.object_name = "p.object", .dds_name = "a.dds", .png_name = "a.png", .tga_name = "a.tga"});
    test.expect(json.find(R"("alpha_coverage": "translucent")") != std::string::npos &&
                    json.find("\"payload_size\": 8") != std::string::npos &&
                    json.find(R"("input_payload_bytes": 8)") != std::string::npos &&
                    json.find(R"("consumed_payload_bytes": 8)") != std::string::npos &&
                    json.find(R"("ignored_payload_bytes": 0)") != std::string::npos &&
                    json.find(R"("payload_extent_basis": "complete_input_payload")") !=
                        std::string::npos,
                "json reports alpha and payload");

    auto short_payload = payload;
    short_payload.pop_back();
    const auto mismatch = tmxy::texture::QtxReader{}.parse(descriptor, short_payload);
    test.expect(!mismatch.has_value() &&
                    mismatch.error().code == tmxy::texture::TextureErrorCode::payload_size_mismatch,
                "payload mismatch rejected");
}

void test_block_alpha(TestContext& test)
{
    const auto dxt1a_body = make_descriptor(tmxy::texture::TextureFormat::dxt1a, 4, 4, 1);
    auto dxt1a_descriptor = parse_descriptor(test, dxt1a_body, "dxt1a descriptor parses");
    std::vector<std::byte> dxt1a(8U, std::byte{0});
    dxt1a[2] = std::byte{0xFF};
    dxt1a[3] = std::byte{0xFF};
    dxt1a[4] = std::byte{0x03};
    auto dxt1a_texture = tmxy::texture::QtxReader{}.parse(dxt1a_descriptor, dxt1a);
    test.expect(dxt1a_texture.has_value() && dxt1a_texture.value().alpha_coverage ==
                                                 tmxy::texture::AlphaCoverage::binary_mask,
                "dxt1a binary alpha decoded");

    const auto dxt3_body = make_descriptor(tmxy::texture::TextureFormat::dxt3, 4, 4, 1);
    auto dxt3_descriptor = parse_descriptor(test, dxt3_body, "dxt3 descriptor parses");
    std::vector<std::byte> dxt3(16U, std::byte{0});
    for (std::size_t index = 0; index < 8U; ++index)
    {
        dxt3[index] = std::byte{0x88};
    }
    auto dxt3_texture = tmxy::texture::QtxReader{}.parse(dxt3_descriptor, dxt3);
    test.expect(dxt3_texture.has_value() && dxt3_texture.value().alpha_coverage ==
                                                tmxy::texture::AlphaCoverage::translucent,
                "dxt3 explicit alpha decoded");

    const auto dxt5_body = make_descriptor(tmxy::texture::TextureFormat::dxt5, 4, 4, 1);
    auto dxt5_descriptor = parse_descriptor(test, dxt5_body, "dxt5 descriptor parses");
    std::vector<std::byte> dxt5(16U, std::byte{0});
    dxt5[1] = std::byte{1};
    auto dxt5_texture = tmxy::texture::QtxReader{}.parse(dxt5_descriptor, dxt5);
    test.expect(dxt5_texture.has_value() && dxt5_texture.value().alpha_coverage ==
                                                tmxy::texture::AlphaCoverage::transparent,
                "dxt5 transparent alpha decoded");
}

void test_float_formats(TestContext& test)
{
    const auto half_body = make_descriptor(tmxy::texture::TextureFormat::rgba16f, 1, 1, 1);
    auto half_descriptor = parse_descriptor(test, half_body, "rgba16f descriptor parses");
    const std::vector<std::byte> half{std::byte{0x00}, std::byte{0x3C}, std::byte{0x00},
                                      std::byte{0x38}, std::byte{0x00}, std::byte{0x00},
                                      std::byte{0x00}, std::byte{0x3C}};
    auto half_texture = tmxy::texture::QtxReader{}.parse(half_descriptor, half);
    test.expect(half_texture.has_value() &&
                    half_texture.value().alpha_coverage == tmxy::texture::AlphaCoverage::opaque,
                "rgba16f decodes finite alpha");
    auto half_dds = half_texture.has_value()
                        ? tmxy::texture::build_dds(half_texture.value(), half)
                        : tmxy::texture::TextureResult<std::vector<std::byte>>::failure({});
    test.expect(half_dds.has_value() && half_dds.value().size() == 156U &&
                    half_dds.value()[84] == std::byte{'D'} &&
                    half_dds.value()[87] == std::byte{'0'},
                "rgba16f uses dx10 dds header");

    const auto float_body = make_descriptor(tmxy::texture::TextureFormat::r32f, 1, 1, 1);
    auto float_descriptor = parse_descriptor(test, float_body, "r32f descriptor parses");
    const std::vector<std::byte> finite{std::byte{0x00}, std::byte{0x00}, std::byte{0x00},
                                        std::byte{0x3F}};
    auto float_texture = tmxy::texture::QtxReader{}.parse(float_descriptor, finite);
    test.expect(float_texture.has_value(), "r32f finite value parses");
    const std::vector<std::byte> infinite{std::byte{0x00}, std::byte{0x00}, std::byte{0x80},
                                          std::byte{0x7F}};
    const auto rejected = tmxy::texture::QtxReader{}.parse(float_descriptor, infinite);
    test.expect(!rejected.has_value() &&
                    rejected.error().code == tmxy::texture::TextureErrorCode::non_finite_pixel,
                "r32f infinity rejected");
}

void test_complete_payload_mip_recovery(TestContext& test)
{
    const auto declared_three = make_descriptor(tmxy::texture::TextureFormat::rgba8, 4, 4, 3);
    const auto descriptor = parse_descriptor(test, declared_three, "recovery descriptor parses");
    std::vector<std::byte> two_complete_mips(80U, std::byte{0});
    const auto strict = tmxy::texture::QtxReader{}.parse(descriptor, two_complete_mips);
    test.expect(!strict.has_value() &&
                    strict.error().code == tmxy::texture::TextureErrorCode::payload_size_mismatch,
                "default QTX binder remains descriptor-strict");

    const auto inferred =
        tmxy::texture::infer_complete_payload_mip_count(descriptor, two_complete_mips);
    test.expect(inferred.has_value() && inferred.value() == 2U,
                "complete payload planner derives one explicit mip count");
    const auto recovered = tmxy::texture::QtxReader{}.parse_with_mip_count_resolution(
        descriptor, two_complete_mips,
        {.effective_mip_count = inferred.has_value() ? inferred.value() : 0U,
         .basis = tmxy::texture::MipCountBasis::payload_complete_chain_contract});
    test.expect(recovered.has_value(), "complete payload mip chain recovers explicitly");
    if (recovered.has_value())
    {
        const auto& value = recovered.value();
        test.expect(value.descriptor.mip_count == 3U && value.effective_mip_count == 2U &&
                        value.mips.size() == 2U &&
                        value.mip_count_basis ==
                            tmxy::texture::MipCountBasis::payload_complete_chain_contract &&
                        value.input_payload_bytes == two_complete_mips.size() &&
                        value.consumed_payload_bytes == two_complete_mips.size() &&
                        value.ignored_payload_bytes == 0U &&
                        value.payload_extent_basis ==
                            tmxy::texture::PayloadExtentBasis::complete_input_payload,
                    "declared and effective mip counts remain distinct");
        const auto json = tmxy::texture::build_texture_json(value, {});
        test.expect(json.find(R"("mip_count": 3)") != std::string::npos &&
                        json.find(R"("effective_mip_count": 2)") != std::string::npos &&
                        json.find(R"("mip_count_basis": "payload_complete_chain_contract")") !=
                            std::string::npos,
                    "QTX JSON discloses recovery basis");
        const auto dds = tmxy::texture::build_dds(value, two_complete_mips);
        const auto load_u32 =
            [](const std::vector<std::byte>& bytes, const std::size_t offset) noexcept
        {
            return static_cast<std::uint32_t>(bytes[offset]) |
                   (static_cast<std::uint32_t>(bytes[offset + 1U]) << 8U) |
                   (static_cast<std::uint32_t>(bytes[offset + 2U]) << 16U) |
                   (static_cast<std::uint32_t>(bytes[offset + 3U]) << 24U);
        };
        test.expect(dds.has_value() && load_u32(dds.value(), 28U) == 2U &&
                        (load_u32(dds.value(), 8U) & 0x00020000U) != 0U &&
                        (load_u32(dds.value(), 108U) & 0x00400008U) == 0x00400008U,
                    "DDS header count flags and caps use the effective mip count");
    }

    auto truncated = two_complete_mips;
    truncated.pop_back();
    test.expect(!tmxy::texture::infer_complete_payload_mip_count(descriptor, truncated).has_value(),
                "partial mip has no recovery plan");
    const auto truncated_result = tmxy::texture::QtxReader{}.parse_with_mip_count_resolution(
        descriptor, truncated,
        {.effective_mip_count = 2U,
         .basis = tmxy::texture::MipCountBasis::payload_complete_chain_contract});
    test.expect(!truncated_result.has_value() &&
                    truncated_result.error().code ==
                        tmxy::texture::TextureErrorCode::payload_size_mismatch,
                "partial mip remains rejected under recovery policy");

    std::vector<std::byte> beyond_natural_chain(85U, std::byte{0});
    const auto trailing_result = tmxy::texture::QtxReader{}.parse_with_mip_count_resolution(
        descriptor, beyond_natural_chain,
        {.effective_mip_count = 3U,
         .basis = tmxy::texture::MipCountBasis::payload_complete_chain_contract});
    test.expect(!trailing_result.has_value() &&
                    trailing_result.error().code ==
                        tmxy::texture::TextureErrorCode::payload_size_mismatch,
                "bytes beyond the natural mip chain remain rejected");

    const auto declared_one = make_descriptor(tmxy::texture::TextureFormat::rgba8, 4, 4, 1);
    const auto short_descriptor =
        parse_descriptor(test, declared_one, "under-declared recovery descriptor parses");
    const auto under_declared = tmxy::texture::QtxReader{}.parse_with_mip_count_resolution(
        short_descriptor, two_complete_mips,
        {.effective_mip_count = 2U,
         .basis = tmxy::texture::MipCountBasis::payload_complete_chain_contract});
    test.expect(!under_declared.has_value() &&
                    under_declared.error().code ==
                        tmxy::texture::TextureErrorCode::invalid_mip_count,
                "explicit recovery cannot add payload mips beyond the declared chain");

    auto implicit_descriptor = descriptor;
    implicit_descriptor.stored_mip_count = 0U;
    implicit_descriptor.mip_count = 1U;
    const auto implicit_declared = tmxy::texture::QtxReader{}.parse_with_mip_count_resolution(
        implicit_descriptor, std::span<const std::byte>(two_complete_mips).first(64U),
        {.effective_mip_count = 1U,
         .basis = tmxy::texture::MipCountBasis::payload_complete_chain_contract});
    test.expect(!implicit_declared.has_value() &&
                    implicit_declared.error().code ==
                        tmxy::texture::TextureErrorCode::invalid_mip_count,
                "recovery requires an explicit stored mip declaration");

    const auto unknown_basis = tmxy::texture::QtxReader{}.parse_with_mip_count_resolution(
        descriptor, two_complete_mips,
        {.effective_mip_count = 2U, .basis = tmxy::texture::MipCountBasis::unknown});
    test.expect(!unknown_basis.has_value() &&
                    unknown_basis.error().code ==
                        tmxy::texture::TextureErrorCode::invalid_mip_count,
                "unknown recovery basis remains rejected");
}

void test_declared_mip_payload_prefix(TestContext& test)
{
    const auto body = make_descriptor(tmxy::texture::TextureFormat::dxt1, 8, 8, 2);
    const auto descriptor = parse_descriptor(test, body, "payload-prefix descriptor parses");
    std::vector<std::byte> declared_payload(40U, std::byte{0});
    const auto declared = tmxy::texture::QtxReader{}.parse(descriptor, declared_payload);
    test.expect(declared.has_value(), "declared two-mip payload remains strict-valid");
    auto longer_payload = declared_payload;
    longer_payload.resize(48U, std::byte{0xA5});
    const auto strict = tmxy::texture::QtxReader{}.parse(descriptor, longer_payload);
    test.expect(!strict.has_value() &&
                    strict.error().code == tmxy::texture::TextureErrorCode::payload_size_mismatch,
                "default parser does not auto-fallback to payload-prefix policy");
    const auto prefix = tmxy::texture::QtxReader{}.parse_with_declared_mip_payload_prefix(
        descriptor, longer_payload);
    test.expect(prefix.has_value(), "explicit policy accepts one longer complete mip");
    if (prefix.has_value() && declared.has_value())
    {
        const auto& value = prefix.value();
        test.expect(value.effective_mip_count == 2U && value.mips.size() == 2U &&
                        value.input_payload_bytes == 48U && value.consumed_payload_bytes == 40U &&
                        value.ignored_payload_bytes == 8U &&
                        value.payload_extent_basis ==
                            tmxy::texture::PayloadExtentBasis::declared_mip_payload_prefix_contract,
                    "view preserves declared mips and discloses byte extents");
        const auto json = tmxy::texture::build_texture_json(value, {});
        test.expect(
            json.find(R"("input_payload_bytes": 48)") != std::string::npos &&
                json.find(R"("consumed_payload_bytes": 40)") != std::string::npos &&
                json.find(R"("ignored_payload_bytes": 8)") != std::string::npos &&
                json.find(R"("payload_extent_basis": "declared_mip_payload_prefix_contract")") !=
                    std::string::npos,
            "JSON discloses payload-prefix byte provenance");
        const auto prefix_dds = tmxy::texture::build_dds(value, longer_payload);
        const auto strict_dds = tmxy::texture::build_dds(declared.value(), declared_payload);
        const auto prefix_png = tmxy::texture::build_png(value, longer_payload);
        const auto strict_png = tmxy::texture::build_png(declared.value(), declared_payload);
        const auto prefix_tga = tmxy::texture::build_tga(value, longer_payload);
        const auto strict_tga = tmxy::texture::build_tga(declared.value(), declared_payload);
        test.expect(prefix_dds.has_value() && strict_dds.has_value() &&
                        prefix_dds.value() == strict_dds.value() &&
                        prefix_dds.value().size() == 168U,
                    "DDS appends only the consumed declared-mip prefix");
        test.expect(prefix_png.has_value() && strict_png.has_value() &&
                        prefix_png.value() == strict_png.value() && prefix_tga.has_value() &&
                        strict_tga.has_value() && prefix_tga.value() == strict_tga.value(),
                    "PNG and TGA decode only mip zero");
        auto unknown_extent = value;
        unknown_extent.payload_extent_basis = tmxy::texture::PayloadExtentBasis::unknown;
        test.expect(!tmxy::texture::build_dds(unknown_extent, longer_payload).has_value() &&
                        !tmxy::texture::build_png(unknown_extent, longer_payload).has_value() &&
                        !tmxy::texture::build_tga(unknown_extent, longer_payload).has_value(),
                    "exporters reject an unknown payload extent basis");

        auto partial_payload = declared_payload;
        partial_payload.resize(41U);
        auto partial_tail = declared.value();
        partial_tail.payload_size = partial_payload.size();
        partial_tail.input_payload_bytes = partial_payload.size();
        partial_tail.ignored_payload_bytes = 1U;
        partial_tail.payload_extent_basis =
            tmxy::texture::PayloadExtentBasis::declared_mip_payload_prefix_contract;
        const auto partial_decode =
            tmxy::texture::decode_mip_zero_rgba8(partial_tail, partial_payload);
        const auto partial_dds = tmxy::texture::build_dds(partial_tail, partial_payload);
        test.expect(!partial_decode.has_value() &&
                        partial_decode.error().code ==
                            tmxy::texture::TextureErrorCode::payload_size_mismatch &&
                        !partial_dds.has_value() &&
                        partial_dds.error().code ==
                            tmxy::texture::TextureErrorCode::payload_size_mismatch,
                    "decode and DDS reject a forged partial trailing mip");

        auto mismatched_extent = value;
        mismatched_extent.consumed_payload_bytes = 39U;
        mismatched_extent.ignored_payload_bytes = 9U;
        mismatched_extent.mips.back().size = 7U;
        const auto mismatched_decode =
            tmxy::texture::decode_mip_zero_rgba8(mismatched_extent, longer_payload);
        const auto mismatched_dds = tmxy::texture::build_dds(mismatched_extent, longer_payload);
        test.expect(!mismatched_decode.has_value() &&
                        mismatched_decode.error().code ==
                            tmxy::texture::TextureErrorCode::payload_size_mismatch &&
                        !mismatched_dds.has_value() &&
                        mismatched_dds.error().code ==
                            tmxy::texture::TextureErrorCode::payload_size_mismatch,
                    "decode and DDS recompute the declared consumed extent");

        auto mismatched_mip = value;
        mismatched_mip.mips.front().offset = 1U;
        const auto mip_decode =
            tmxy::texture::decode_mip_zero_rgba8(mismatched_mip, longer_payload);
        const auto mip_dds = tmxy::texture::build_dds(mismatched_mip, longer_payload);
        test.expect(
            !mip_decode.has_value() &&
                mip_decode.error().code == tmxy::texture::TextureErrorCode::payload_size_mismatch &&
                !mip_dds.has_value() &&
                mip_dds.error().code == tmxy::texture::TextureErrorCode::payload_size_mismatch,
            "decode and DDS reject forged canonical mip metadata");
    }
    const auto reject = [&](const tmxy::texture::TextureDescriptor& candidate,
                            const std::vector<std::byte>& payload, const std::string_view message)
    {
        test.expect(!tmxy::texture::QtxReader{}
                         .parse_with_declared_mip_payload_prefix(candidate, payload)
                         .has_value(),
                    message);
    };
    reject(descriptor, std::vector<std::byte>(49U), "partial trailing mip is rejected");
    reject(descriptor, std::vector<std::byte>(57U), "bytes beyond the natural chain are rejected");
    reject(descriptor, std::vector<std::byte>(32U), "short complete chain is rejected");
    reject(descriptor, declared_payload, "unchanged declared extent is rejected");
    auto mismatched = descriptor;
    mismatched.stored_mip_count = 1U;
    reject(mismatched, longer_payload, "stored and canonical mip counts must match");
    auto implicit = descriptor;
    implicit.stored_mip_count = 0U;
    implicit.mip_count = 1U;
    reject(implicit, declared_payload, "implicit mip count cannot authorize a prefix");
}

} // namespace

int main()
{
    TestContext test;
    test_descriptor(test);
    test_rgba_outputs(test);
    test_block_alpha(test);
    test_float_formats(test);
    test_complete_payload_mip_recovery(test);
    test_declared_mip_payload_prefix(test);
    return test.result();
}
