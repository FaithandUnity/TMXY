#include "skeletal_mesh_gltf_internal.hpp"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <sstream>
#include <string>
#include <string_view>

namespace tmxy::skeletal_mesh::detail
{
namespace
{

[[nodiscard]] std::string json_string(const std::string_view value)
{
    std::ostringstream output;
    output << '"';
    for (const char raw : value)
    {
        const auto character = static_cast<unsigned char>(raw);
        if (character == '"' || character == '\\')
        {
            output << '\\' << raw;
        }
        else if (character >= 0x20U && character < 0x7FU)
        {
            output << raw;
        }
        else
        {
            output << "\\u00" << std::hex << std::setw(2) << std::setfill('0')
                   << static_cast<unsigned int>(character) << std::dec;
        }
    }
    output << '"';
    return output.str();
}

[[nodiscard]] std::array<float, 3> to_gltf(const Vec3& value) noexcept
{
    return {value.y, value.z, value.x};
}

[[nodiscard]] std::array<float, 4> normalized_gltf(const Quaternion& value) noexcept
{
    std::array mapped{value.y, value.z, value.x, value.w};
    float length_squared = 0.0F;
    for (const float component : mapped)
    {
        length_squared += component * component;
    }
    const auto length = std::sqrt(length_squared);
    for (float& component : mapped)
    {
        component /= length;
    }
    return mapped;
}

void write_range(std::ostringstream& output, const ByteRange& range)
{
    output << R"({"buffer": 0, "byteOffset": )" << range.offset << R"(, "byteLength": )"
           << range.size;
    if (range.target != 0)
    {
        output << R"(, "target": )" << range.target;
    }
    output << '}';
}

void write_vec3(std::ostringstream& output, const std::array<float, 3>& value)
{
    output << '[' << value[0] << ", " << value[1] << ", " << value[2] << ']';
}

void write_nodes(std::ostringstream& output, const SkeletalMeshBinding& binding)
{
    const auto& descriptor = binding.package.descriptor;
    output << "  \"nodes\": [\n";
    for (const auto& bone : descriptor.bones)
    {
        const auto translation = to_gltf(bone.translation);
        const auto rotation = normalized_gltf(bone.rotation);
        output << R"(    {"name": )" << json_string(bone.name_bytes) << R"(, "translation": )";
        write_vec3(output, translation);
        output << R"(, "rotation": [)" << rotation[0] << ", " << rotation[1] << ", " << rotation[2]
               << ", " << rotation[3] << ']';
        if (!bone.children.empty())
        {
            output << R"(, "children": [)";
            for (std::size_t child = 0; child < bone.children.size(); ++child)
            {
                output << bone.children[child] << (child + 1U == bone.children.size() ? "" : ", ");
            }
            output << ']';
        }
        output << "},\n";
    }
    output << R"(    {"name": )" << json_string(binding.package.object_name_bytes)
           << R"(, "mesh": 0, "skin": 0})" << "\n  ],\n";
}

void write_views(std::ostringstream& output, const BinaryLayout& layout)
{
    output << "  \"bufferViews\": [\n";
    for (const auto& range : layout.attributes)
    {
        output << "    ";
        write_range(output, range);
        output << ",\n";
    }
    for (std::size_t index = 0; index < layout.primitives.size(); ++index)
    {
        output << "    ";
        write_range(output, layout.primitives[index].indices);
        output << (index + 1U == layout.primitives.size() ? "\n" : ",\n");
    }
    output << "  ],\n";
}

void write_accessors(std::ostringstream& output, const BinaryLayout& layout,
                     const std::size_t bone_count)
{
    output << "  \"accessors\": [\n"
           << R"(    {"bufferView": 0, "componentType": 5126, "count": )" << layout.vertex_count
           << R"(, "type": "VEC3", "min": )";
    write_vec3(output, layout.minimum);
    output << R"(, "max": )";
    write_vec3(output, layout.maximum);
    output << "},\n"
           << R"(    {"bufferView": 1, "componentType": 5126, "count": )" << layout.vertex_count
           << R"(, "type": "VEC3"},)" << '\n'
           << R"(    {"bufferView": 2, "componentType": 5126, "count": )" << layout.vertex_count
           << R"(, "type": "VEC2"},)" << '\n'
           << R"(    {"bufferView": 3, "componentType": 5123, "count": )" << layout.vertex_count
           << R"(, "type": "VEC4"},)" << '\n'
           << R"(    {"bufferView": 4, "componentType": 5126, "count": )" << layout.vertex_count
           << R"(, "type": "VEC4"},)" << '\n'
           << R"(    {"bufferView": 5, "componentType": 5126, "count": )" << bone_count
           << R"(, "type": "MAT4"})";
    for (std::size_t index = 0; index < layout.primitives.size(); ++index)
    {
        output << ",\n"
               << R"(    {"bufferView": )" << 6U + index << R"(, "componentType": 5125, "count": )"
               << layout.primitives[index].indices.size / sizeof(std::uint32_t)
               << R"(, "type": "SCALAR"})";
    }
    output << "\n  ],\n";
}

void write_materials(std::ostringstream& output, const BinaryLayout& layout)
{
    output << "  \"materials\": [\n";
    for (std::size_t index = 0; index < layout.primitives.size(); ++index)
    {
        const auto& primitive = layout.primitives[index];
        output << R"(    {"name": )" << json_string(primitive.name) << R"(, "doubleSided": )"
               << (primitive.two_sided ? "true" : "false")
               << R"(, "extras": {"tmxyLegacyMaterial": )" << json_string(primitive.legacy_material)
               << "}}" << (index + 1U == layout.primitives.size() ? "\n" : ",\n");
    }
    output << "  ],\n";
}

void write_mesh(std::ostringstream& output, const SkeletalMeshBinding& binding,
                const BinaryLayout& layout)
{
    output << R"(  "meshes": [{"name": )" << json_string(binding.package.object_name_bytes)
           << R"(, "primitives": [)" << '\n';
    for (std::size_t index = 0; index < layout.primitives.size(); ++index)
    {
        output
            << R"(    {"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2, "JOINTS_0": 3, "WEIGHTS_0": 4}, "indices": )"
            << 6U + index << R"(, "material": )" << index << R"(, "mode": 4})"
            << (index + 1U == layout.primitives.size() ? "\n" : ",\n");
    }
    output << "  ]}],\n";
}

void write_scene_and_skin(std::ostringstream& output, const SkeletalMeshBinding& binding)
{
    const auto& descriptor = binding.package.descriptor;
    output << R"(  "scene": 0,)" << '\n' << R"(  "scenes": [{"nodes": [)";
    for (const auto root : descriptor.root_bone_ids)
    {
        output << root << ", ";
    }
    output << descriptor.bones.size() << "]}],\n";
    write_nodes(output, binding);
    output << R"(  "skins": [{"name": "TMXY_BindPose", "inverseBindMatrices": 5, "skeleton": )"
           << descriptor.root_bone_ids.front() << R"(, "joints": [)";
    for (std::size_t index = 0; index < descriptor.bones.size(); ++index)
    {
        output << index << (index + 1U == descriptor.bones.size() ? "" : ", ");
    }
    output << "]}],\n";
}

} // namespace

std::string build_gltf_json(const SkeletalMeshBinding& binding, const BinaryLayout& layout,
                            const std::string_view buffer_uri)
{
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<float>::max_digits10) << "{\n"
           << R"(  "asset": {"version": "2.0", "generator": "TMXY.SkeletalMesh 0.2.0"},)" << '\n';
    write_scene_and_skin(output, binding);
    output << R"(  "buffers": [{"uri": )" << json_string(buffer_uri) << R"(, "byteLength": )"
           << layout.bytes.size() << "}],\n";
    write_views(output, layout);
    write_accessors(output, layout, binding.package.descriptor.bones.size());
    write_materials(output, layout);
    write_mesh(output, binding, layout);
    output
        << R"tmxy(  "extras": {"tmxyAssetKind": "skeletal_mesh", "tmxyCoordinateMapping": "legacy(x,y,z)-to-gltf(y,z,x)", "tmxyBoneIndexMapping": "legacy-one-based-to-gltf-zero-based", "tmxyWinding": "preserved"})tmxy"
        << '\n'
        << "}\n";
    return output.str();
}

} // namespace tmxy::skeletal_mesh::detail
