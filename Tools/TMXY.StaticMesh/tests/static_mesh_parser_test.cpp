#include "tmxy/static_mesh/package_static_mesh_reader.hpp"
#include "tmxy/static_mesh/sm_reader.hpp"
#include "tmxy/static_mesh/static_mesh_error.hpp"
#include "tmxy/static_mesh/static_mesh_export.hpp"

#include <bit>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
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
        if (!condition)
        {
            ++failures_;
            std::cerr << "FAILED: " << message << '\n';
        }
    }

    [[nodiscard]] int failures() const noexcept
    {
        return failures_;
    }

  private:
    int failures_{0};
};

void append_u8(std::vector<std::byte>& bytes, const std::uint8_t value)
{
    bytes.push_back(static_cast<std::byte>(value));
}

void append_u16(std::vector<std::byte>& bytes, const std::uint16_t value)
{
    append_u8(bytes, static_cast<std::uint8_t>(value & 0xFFU));
    append_u8(bytes, static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
}

void append_i32(std::vector<std::byte>& bytes, const std::int32_t value)
{
    const auto raw = std::bit_cast<std::uint32_t>(value);
    for (unsigned int shift = 0; shift < 32U; shift += 8U)
    {
        append_u8(bytes, static_cast<std::uint8_t>((raw >> shift) & 0xFFU));
    }
}

void append_f32(std::vector<std::byte>& bytes, const float value)
{
    append_i32(bytes, std::bit_cast<std::int32_t>(value));
}

void append_vec3(std::vector<std::byte>& bytes, const float x, const float y, const float z)
{
    append_f32(bytes, x);
    append_f32(bytes, y);
    append_f32(bytes, z);
}

void append_vec2(std::vector<std::byte>& bytes, const float u, const float v)
{
    append_f32(bytes, u);
    append_f32(bytes, v);
}

void append_render_vec3_array(std::vector<std::byte>& bytes, const float z)
{
    append_i32(bytes, 3);
    append_vec3(bytes, 0.0F, 0.0F, z);
    append_vec3(bytes, 1.0F, 0.0F, z);
    append_vec3(bytes, 0.0F, 1.0F, z);
}

struct MeshOptions final
{
    std::uint16_t third_index{2U};
    std::uint8_t two_sided{0U};
    bool append_extra{false};
};

[[nodiscard]] std::vector<std::byte> make_mesh(const MeshOptions options = {})
{
    std::vector<std::byte> bytes;
    append_render_vec3_array(bytes, 0.0F);
    append_i32(bytes, 3);
    for (int index = 0; index < 3; ++index)
    {
        append_vec3(bytes, 0.0F, 0.0F, 1.0F);
    }
    append_i32(bytes, 3);
    append_vec2(bytes, 0.0F, 0.0F);
    append_vec2(bytes, 1.0F, 0.0F);
    append_vec2(bytes, 0.0F, 1.0F);
    append_i32(bytes, 3);
    for (int index = 0; index < 3; ++index)
    {
        append_vec3(bytes, 1.0F, 0.0F, 0.0F);
    }
    append_i32(bytes, 3);
    for (int index = 0; index < 3; ++index)
    {
        append_vec3(bytes, 0.0F, 1.0F, 0.0F);
    }
    append_i32(bytes, 3);
    append_u16(bytes, 0U);
    append_u16(bytes, 1U);
    append_u16(bytes, options.third_index);
    append_i32(bytes, 1);
    append_i32(bytes, 1);
    append_i32(bytes, 0);
    append_i32(bytes, 2);
    append_u8(bytes, options.two_sided);
    for (int array = 0; array < 5; ++array)
    {
        append_i32(bytes, 0);
    }
    append_i32(bytes, 0);
    append_i32(bytes, 0);
    append_i32(bytes, 0);
    if (options.append_extra)
    {
        append_i32(bytes, 0);
        append_u8(bytes, 0xAAU);
    }
    return bytes;
}

void append_property(std::vector<std::byte>& body, const std::string_view name,
                     const std::span<const std::byte> value)
{
    append_u16(body, static_cast<std::uint16_t>(name.size()));
    for (const char character : name)
    {
        append_u8(body, static_cast<std::uint8_t>(character));
    }
    append_u16(body, static_cast<std::uint16_t>(value.size()));
    body.insert(body.end(), value.begin(), value.end());
}

[[nodiscard]] std::vector<std::byte> u16_value(const std::uint16_t value)
{
    std::vector<std::byte> bytes;
    append_u16(bytes, value);
    return bytes;
}

[[nodiscard]] std::vector<std::byte> string_value(const std::string_view value)
{
    std::vector<std::byte> bytes;
    append_u16(bytes, static_cast<std::uint16_t>(value.size()));
    for (const char character : value)
    {
        append_u8(bytes, static_cast<std::uint8_t>(character));
    }
    return bytes;
}

[[nodiscard]] std::vector<std::byte> float_value(const float value)
{
    std::vector<std::byte> bytes;
    append_f32(bytes, value);
    return bytes;
}

[[nodiscard]] std::vector<std::byte> make_descriptor(const bool duplicate_slot = false)
{
    std::vector<std::byte> body;
    append_u16(body, static_cast<std::uint16_t>(9 + (duplicate_slot ? 1 : 0)));
    const auto count = u16_value(1U);
    const auto material = string_value("sample.material");
    append_property(body, "skins", count);
    append_property(body, "skins[0]", material);
    if (duplicate_slot)
    {
        append_property(body, "skins[0]", material);
    }
    append_property(body, "bBox.min.x", float_value(0.0F));
    append_property(body, "bBox.min.y", float_value(0.0F));
    append_property(body, "bBox.min.z", float_value(0.0F));
    append_property(body, "bBox.max.x", float_value(1.0F));
    append_property(body, "bBox.max.y", float_value(1.0F));
    append_property(body, "bBox.max.z", float_value(0.0F));
    const std::vector<std::byte> future{std::byte{0xAB}};
    append_property(body, "future.property", future);
    return body;
}

void test_valid_mesh_and_export(TestContext& test)
{
    const auto bytes = make_mesh();
    const auto parsed = tmxy::static_mesh::SmReader{}.parse(bytes);
    test.expect(parsed.has_value(), "valid synthetic mesh parses");
    if (!parsed.has_value())
    {
        return;
    }
    test.expect(parsed.value().positions.size() == 3U, "vertex count preserved");
    test.expect(parsed.value().indices.size() == 3U, "index count preserved");
    test.expect(parsed.value().sections.size() == 1U, "section count preserved");
    test.expect(parsed.value().emitter_points_field_present, "emitter tail detected");

    const auto descriptor_bytes = make_descriptor();
    const auto descriptor = tmxy::static_mesh::read_static_mesh_descriptor(descriptor_bytes);
    test.expect(descriptor.has_value(), "valid synthetic descriptor parses");
    if (!descriptor.has_value())
    {
        return;
    }
    test.expect(descriptor.value().unknown_properties.size() == 1U &&
                    descriptor.value().unknown_properties[0].name_bytes == "future.property" &&
                    descriptor.value().unknown_properties[0].value ==
                        std::vector<std::byte>{std::byte{0xAB}},
                "unknown static-mesh property is preserved byte-for-byte");
    tmxy::static_mesh::StaticMeshBinding binding{
        .mesh = parsed.value(),
        .package = {.object_name_bytes = "sample.mesh", .descriptor = descriptor.value()},
        .effective_bounds = parsed.value().render_bounds,
        .declared_bounds_relation = tmxy::static_mesh::DeclaredBoundsRelation::exact};
    const auto first = tmxy::static_mesh::build_ue_obj(binding);
    const auto second = tmxy::static_mesh::build_ue_obj(binding);
    test.expect(first.has_value(), "UE OBJ preview builds");
    test.expect(first.has_value() && second.has_value() && first.value() == second.value(),
                "UE OBJ preview is deterministic");
    test.expect(first.has_value() && first.value().find("v 100 0 0") != std::string::npos,
                "legacy meters convert to UE centimeters");
    const auto json = tmxy::static_mesh::build_static_mesh_json(binding);
    test.expect(json.find(R"("material": "sample.material")") != std::string::npos,
                "material slot is emitted");
}

void test_corrupt_meshes(TestContext& test)
{
    auto negative = make_mesh();
    negative[0] = std::byte{0xFF};
    negative[1] = std::byte{0xFF};
    negative[2] = std::byte{0xFF};
    negative[3] = std::byte{0xFF};
    const auto negative_result = tmxy::static_mesh::SmReader{}.parse(negative);
    test.expect(!negative_result.has_value() &&
                    negative_result.error().code ==
                        tmxy::static_mesh::StaticMeshErrorCode::negative_count,
                "negative count rejected");

    auto truncated = make_mesh();
    truncated.pop_back();
    const auto truncated_result = tmxy::static_mesh::SmReader{}.parse(truncated);
    test.expect(!truncated_result.has_value(), "truncated tail rejected");

    const auto bad_index = tmxy::static_mesh::SmReader{}.parse(make_mesh({.third_index = 7U}));
    test.expect(!bad_index.has_value() &&
                    bad_index.error().code ==
                        tmxy::static_mesh::StaticMeshErrorCode::index_out_of_range,
                "out-of-range index rejected");

    const auto bad_bool = tmxy::static_mesh::SmReader{}.parse(make_mesh({.two_sided = 2U}));
    test.expect(!bad_bool.has_value() &&
                    bad_bool.error().code ==
                        tmxy::static_mesh::StaticMeshErrorCode::invalid_boolean,
                "non-canonical bool rejected");

    const auto trailing = tmxy::static_mesh::SmReader{}.parse(make_mesh({.append_extra = true}));
    test.expect(!trailing.has_value() &&
                    trailing.error().code == tmxy::static_mesh::StaticMeshErrorCode::trailing_bytes,
                "third optional tail rejected");
}

void test_corrupt_descriptor(TestContext& test)
{
    const auto duplicate =
        tmxy::static_mesh::read_static_mesh_descriptor(make_descriptor(true), 100U);
    test.expect(!duplicate.has_value() &&
                    duplicate.error().code ==
                        tmxy::static_mesh::StaticMeshErrorCode::duplicate_property,
                "duplicate material slot rejected");

    auto non_finite = make_descriptor();
    const auto infinity = std::bit_cast<std::uint32_t>(std::numeric_limits<float>::infinity());
    const auto marker = std::bit_cast<std::uint32_t>(1.0F);
    for (std::size_t offset = 0; offset + 4U <= non_finite.size(); ++offset)
    {
        std::uint32_t value = 0;
        for (unsigned int shift = 0; shift < 32U; shift += 8U)
        {
            value |= static_cast<std::uint32_t>(
                         std::to_integer<std::uint8_t>(non_finite[offset + (shift / 8U)]))
                     << shift;
        }
        if (value == marker)
        {
            for (unsigned int shift = 0; shift < 32U; shift += 8U)
            {
                non_finite[offset + (shift / 8U)] =
                    static_cast<std::byte>((infinity >> shift) & 0xFFU);
            }
            break;
        }
    }
    const auto invalid = tmxy::static_mesh::read_static_mesh_descriptor(non_finite);
    test.expect(!invalid.has_value() &&
                    invalid.error().code ==
                        tmxy::static_mesh::StaticMeshErrorCode::non_finite_component,
                "non-finite declared bound rejected");
}

} // namespace

int main()
{
    TestContext test;
    test_valid_mesh_and_export(test);
    test_corrupt_meshes(test);
    test_corrupt_descriptor(test);
    test.expect(tmxy::static_mesh::StaticMeshError::kSchemaVersion == 1U,
                "error schema version is frozen");
    test.expect(tmxy::static_mesh::to_string(
                    tmxy::static_mesh::StaticMeshErrorCode::material_slot_mismatch) ==
                    "material_slot_mismatch",
                "stable error code name");
    return test.failures() == 0 ? 0 : 1;
}
