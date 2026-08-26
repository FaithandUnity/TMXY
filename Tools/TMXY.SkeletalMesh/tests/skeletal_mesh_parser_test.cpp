#include "tmxy/skeletal_mesh/package_skeletal_mesh_reader.hpp"
#include "tmxy/skeletal_mesh/skeletal_mesh_error.hpp"
#include "tmxy/skeletal_mesh/skeletal_mesh_export.hpp"
#include "tmxy/skeletal_mesh/skeletal_mesh_gltf.hpp"
#include "tmxy/skeletal_mesh/skem_reader.hpp"

#include <bit>
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

void append_vec2(std::vector<std::byte>& bytes, const float u, const float v)
{
    append_f32(bytes, u);
    append_f32(bytes, v);
}

void append_vec3(std::vector<std::byte>& bytes, const float x, const float y, const float z)
{
    append_f32(bytes, x);
    append_f32(bytes, y);
    append_f32(bytes, z);
}

void append_vec4(std::vector<std::byte>& bytes, const float x, const float y, const float z,
                 const float w)
{
    append_f32(bytes, x);
    append_f32(bytes, y);
    append_f32(bytes, z);
    append_f32(bytes, w);
}

void append_string(std::vector<std::byte>& bytes, const std::string_view value)
{
    append_u16(bytes, static_cast<std::uint16_t>(value.size()));
    for (const char character : value)
    {
        append_u8(bytes, static_cast<std::uint8_t>(character));
    }
}

template <typename AppendValue>
void append_array(std::vector<std::byte>& bytes, const std::int32_t count, AppendValue append_value)
{
    append_i32(bytes, count);
    for (std::int32_t index = 0; index < count; ++index)
    {
        append_value(index);
    }
}

struct PayloadOptions final
{
    float first_weight{1.0F};
    bool sentinel_first{false};
    bool append_trailing{false};
};

[[nodiscard]] std::vector<std::byte> make_payload(const PayloadOptions options = {})
{
    std::vector<std::byte> bytes;
    append_i32(bytes, 1);
    append_i32(bytes, 0);
    append_i32(bytes, 1);
    append_string(bytes, "body");
    append_i32(bytes, 0);
    append_array(bytes, 3, [&](const std::int32_t index)
                 { append_vec3(bytes, index == 1 ? 1.0F : 0.0F, index == 2 ? 1.0F : 0.0F, 0.0F); });
    append_array(bytes, 3, [&](const std::int32_t) { append_vec3(bytes, 0.0F, 0.0F, 1.0F); });
    append_array(bytes, 3, [&](const std::int32_t index)
                 { append_vec2(bytes, index == 1 ? 1.0F : 0.0F, index == 2 ? 1.0F : 0.0F); });
    append_array(bytes, 3, [&](const std::int32_t) { append_vec3(bytes, 1.0F, 0.0F, 0.0F); });
    append_array(bytes, 3, [&](const std::int32_t) { append_vec3(bytes, 0.0F, 1.0F, 0.0F); });
    append_array(bytes, 3,
                 [&](const std::int32_t index)
                 {
                     if (index == 0 && options.sentinel_first)
                     {
                         append_vec4(bytes, -1.0F, -1.0F, -1.0F, -1.0F);
                         return;
                     }
                     const auto first = index == 0 ? options.first_weight : 1.0F;
                     append_vec4(bytes, first, 0.0F, 0.0F, 0.0F);
                 });
    append_array(bytes, 3,
                 [&](const std::int32_t index)
                 {
                     const auto bone = index == 0 && options.sentinel_first ? 0.0F : 1.0F;
                     append_vec4(bytes, bone, 0.0F, 0.0F, 0.0F);
                 });
    append_i32(bytes, 3);
    append_u16(bytes, 0U);
    append_u16(bytes, 1U);
    append_u16(bytes, 2U);
    append_i32(bytes, 1);
    append_i32(bytes, 1);
    append_i32(bytes, 0);
    append_i32(bytes, 2);
    append_u8(bytes, 0U);
    append_i32(bytes, 3);
    append_u16(bytes, 0U);
    append_u16(bytes, 1U);
    append_u16(bytes, 2U);
    append_i32(bytes, 1);
    append_i32(bytes, -1);
    append_i32(bytes, -1);
    append_i32(bytes, -1);
    if (options.append_trailing)
    {
        append_u8(bytes, 0xAAU);
    }
    return bytes;
}

void append_property(std::vector<std::byte>& body, std::uint16_t& count,
                     const std::string_view name, const std::span<const std::byte> value)
{
    ++count;
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

[[nodiscard]] std::vector<std::byte> i32_value(const std::int32_t value)
{
    std::vector<std::byte> bytes;
    append_i32(bytes, value);
    return bytes;
}

[[nodiscard]] std::vector<std::byte> f32_value(const float value)
{
    std::vector<std::byte> bytes;
    append_f32(bytes, value);
    return bytes;
}

[[nodiscard]] std::vector<std::byte> string_value(const std::string_view value)
{
    std::vector<std::byte> bytes;
    append_string(bytes, value);
    return bytes;
}

void append_bone(std::vector<std::byte>& body, std::uint16_t& count, const std::uint16_t index,
                 const std::string_view name, const bool has_child)
{
    const auto prefix = "_skel[" + std::to_string(index) + "]";
    const std::vector<std::byte> empty;
    append_property(body, count, prefix, empty);
    append_property(body, count, prefix + "._ID", i32_value(index));
    append_property(body, count, prefix + "._name", string_value(name));
    append_property(body, count, prefix + "._rotPose", empty);
    append_property(body, count, prefix + "._rotPose.x", f32_value(0.0F));
    append_property(body, count, prefix + "._rotPose.y", f32_value(0.0F));
    append_property(body, count, prefix + "._rotPose.z", f32_value(0.0F));
    append_property(body, count, prefix + "._rotPose.w", f32_value(1.0F));
    append_property(body, count, prefix + "._tranPose", empty);
    append_property(body, count, prefix + "._tranPose.x", f32_value(index));
    append_property(body, count, prefix + "._tranPose.y", f32_value(0.0F));
    append_property(body, count, prefix + "._tranPose.z", f32_value(0.0F));
    append_property(body, count, prefix + "._children", u16_value(has_child ? 1U : 0U));
    if (has_child)
    {
        append_property(body, count, prefix + "._children[0]", i32_value(1));
    }
}

[[nodiscard]] std::vector<std::byte> make_descriptor()
{
    std::vector<std::byte> properties;
    std::uint16_t count = 0;
    append_property(properties, count, "_skel", u16_value(2U));
    append_bone(properties, count, 0U, "root", true);
    append_bone(properties, count, 1U, "hand_socket", false);
    append_property(properties, count, "_anim", u16_value(0U));
    append_property(properties, count, "defaultAnim", string_value("idle"));
    append_property(properties, count, "defaultSecs", u16_value(1U));
    append_property(properties, count, "defaultSecs[0]", i32_value(0));
    append_property(properties, count, "skins", u16_value(1U));
    append_property(properties, count, "skins[0]", string_value("sample.material"));
    append_property(properties, count, "bBox.min.x", f32_value(0.0F));
    append_property(properties, count, "bBox.min.y", f32_value(0.0F));
    append_property(properties, count, "bBox.min.z", f32_value(0.0F));
    append_property(properties, count, "bBox.max.x", f32_value(1.0F));
    append_property(properties, count, "bBox.max.y", f32_value(1.0F));
    append_property(properties, count, "bBox.max.z", f32_value(0.0F));
    const std::vector<std::byte> future{std::byte{0xCD}};
    append_property(properties, count, "future.property", future);
    std::vector<std::byte> body;
    append_u16(body, count);
    body.insert(body.end(), properties.begin(), properties.end());
    return body;
}

void test_valid_payload(TestContext& test)
{
    const auto parsed = tmxy::skeletal_mesh::SkemReader{}.parse(make_payload());
    test.expect(parsed.has_value(), "valid synthetic skem parses");
    if (!parsed.has_value())
    {
        return;
    }
    test.expect(parsed.value().groups.size() == 1U, "group count preserved");
    test.expect(parsed.value().total_submesh_count == 1U, "submesh count preserved");
    test.expect(parsed.value().total_vertex_count == 3U, "vertex count preserved");
    test.expect(parsed.value().total_triangle_count == 1U, "triangle count preserved");
}

void test_valid_descriptor_and_export(TestContext& test)
{
    auto descriptor = tmxy::skeletal_mesh::read_skeletal_mesh_descriptor(make_descriptor());
    test.expect(descriptor.has_value(), "valid synthetic QSkelMesh descriptor parses");
    auto payload = tmxy::skeletal_mesh::SkemReader{}.parse(make_payload());
    if (!descriptor.has_value() || !payload.has_value())
    {
        return;
    }
    test.expect(descriptor.value().bones.size() == 2U, "bone count preserved");
    test.expect(descriptor.value().bones[1].parent_id == 0, "parent derived from child list");
    test.expect(descriptor.value().root_bone_ids == std::vector<std::int32_t>{0},
                "root bone derived");
    test.expect(descriptor.value().unknown_properties.size() == 1U &&
                    descriptor.value().unknown_properties[0].name_bytes == "future.property" &&
                    descriptor.value().unknown_properties[0].value ==
                        std::vector<std::byte>{std::byte{0xCD}},
                "unknown skeletal-mesh property is preserved byte-for-byte");
    tmxy::skeletal_mesh::SkeletalMeshBinding binding{
        .payload = payload.value(),
        .package = {.object_name_bytes = "sample.mesh", .descriptor = descriptor.value()},
        .default_selections = {{.group_index = 0,
                                .global_submesh_index = 0,
                                .submesh_index_in_group = 0,
                                .material_object_name = "sample.material"}}};
    const auto first = tmxy::skeletal_mesh::build_default_ue_obj(binding);
    const auto second = tmxy::skeletal_mesh::build_default_ue_obj(binding);
    test.expect(first.has_value() && second.has_value() && first.value() == second.value(),
                "default-selection OBJ is deterministic");
    test.expect(first.has_value() && first.value().find("v 100 0 0") != std::string::npos,
                "OBJ converts legacy meters to UE centimeters");
    const auto json = tmxy::skeletal_mesh::build_skeletal_mesh_json(binding);
    test.expect(json.find(R"("parent_id": 0)") != std::string::npos,
                "JSON emits skeleton hierarchy");
    test.expect(json.find("hand_socket") != std::string::npos,
                "JSON exposes bone-name attachment candidate");
    const auto gltf = tmxy::skeletal_mesh::build_default_gltf2(binding, "sample.bin");
    const auto repeated = tmxy::skeletal_mesh::build_default_gltf2(binding, "sample.bin");
    test.expect(gltf.has_value() && repeated.has_value() &&
                    gltf.value().json == repeated.value().json &&
                    gltf.value().binary == repeated.value().binary,
                "skinned glTF output is deterministic");
    test.expect(gltf.has_value() &&
                    gltf.value().json.find(R"("JOINTS_0": 3, "WEIGHTS_0": 4)") !=
                        std::string::npos &&
                    gltf.value().json.find(R"("inverseBindMatrices": 5)") != std::string::npos &&
                    gltf.value().json.find(R"("translation": [0, 0, 1])") != std::string::npos,
                "glTF preserves skinning, bind pose and cyclic coordinate mapping");
    test.expect(!tmxy::skeletal_mesh::build_default_gltf2(binding, "../unsafe.bin").has_value(),
                "glTF rejects unsafe external buffer URI");
}

void test_corruption(TestContext& test)
{
    auto negative = make_payload();
    negative[0] = std::byte{0xFF};
    negative[1] = std::byte{0xFF};
    negative[2] = std::byte{0xFF};
    negative[3] = std::byte{0xFF};
    const auto negative_result = tmxy::skeletal_mesh::SkemReader{}.parse(negative);
    test.expect(!negative_result.has_value() &&
                    negative_result.error().code ==
                        tmxy::skeletal_mesh::SkeletalMeshErrorCode::negative_count,
                "negative group count rejected");

    const auto bad_weight =
        tmxy::skeletal_mesh::SkemReader{}.parse(make_payload({.first_weight = 0.5F}));
    test.expect(!bad_weight.has_value() &&
                    bad_weight.error().code ==
                        tmxy::skeletal_mesh::SkeletalMeshErrorCode::invalid_weight,
                "non-normalized weights rejected");

    const auto trailing =
        tmxy::skeletal_mesh::SkemReader{}.parse(make_payload({.append_trailing = true}));
    test.expect(!trailing.has_value() &&
                    trailing.error().code ==
                        tmxy::skeletal_mesh::SkeletalMeshErrorCode::trailing_bytes,
                "trailing bytes rejected");

    const auto sentinel =
        tmxy::skeletal_mesh::SkemReader{}.parse(make_payload({.sentinel_first = true}));
    test.expect(sentinel.has_value(), "exact legacy -1 weight/zero-bone sentinel is preserved");

    auto truncated = make_payload();
    truncated.pop_back();
    test.expect(!tmxy::skeletal_mesh::SkemReader{}.parse(truncated).has_value(),
                "truncated adjacency rejected");
}

} // namespace

int main()
{
    TestContext test;
    test_valid_payload(test);
    test_valid_descriptor_and_export(test);
    test_corruption(test);
    test.expect(tmxy::skeletal_mesh::SkeletalMeshError::kSchemaVersion == 1U,
                "error schema version is frozen");
    test.expect(tmxy::skeletal_mesh::to_string(
                    tmxy::skeletal_mesh::SkeletalMeshErrorCode::cyclic_skeleton) ==
                    "cyclic_skeleton",
                "stable error code name");
    return test.failures() == 0 ? 0 : 1;
}
