#include "tmxy/static_mesh/static_mesh_gltf.hpp"

#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace tmxy::static_mesh
{
namespace
{

struct ByteRange final
{
    std::size_t offset{0};
    std::size_t size{0};
};

struct BinaryLayout final
{
    std::vector<std::byte> bytes;
    ByteRange positions;
    ByteRange normals;
    ByteRange uv0;
    std::optional<ByteRange> uv1;
    ByteRange indices;
    std::array<float, 3> minimum{};
    std::array<float, 3> maximum{};
};

[[nodiscard]] StaticMeshError gltf_error(std::string context)
{
    return {.code = StaticMeshErrorCode::transform_failure,
            .absolute_offset = 0,
            .context = std::move(context),
            .read_error_code = std::nullopt};
}

[[nodiscard]] bool is_safe_buffer_uri(const std::string_view value) noexcept
{
    if (value.empty() || value == "." || value == "..")
    {
        return false;
    }
    return std::ranges::all_of(value,
                               [](const char character)
                               {
                                   return (character >= 'a' && character <= 'z') ||
                                          (character >= 'A' && character <= 'Z') ||
                                          (character >= '0' && character <= '9') ||
                                          character == '.' || character == '_' || character == '-';
                               });
}

[[nodiscard]] std::string json_string(const std::string_view value)
{
    std::ostringstream output;
    output << '"';
    for (const char raw_character : value)
    {
        const auto character = static_cast<unsigned char>(raw_character);
        if (character == '"' || character == '\\')
        {
            output << '\\' << raw_character;
        }
        else if (character >= 0x20U && character < 0x7FU)
        {
            output << raw_character;
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

void align_four(std::vector<std::byte>& bytes)
{
    while ((bytes.size() & 3U) != 0U)
    {
        bytes.push_back(std::byte{0});
    }
}

void append_u16(std::vector<std::byte>& bytes, const std::uint16_t value)
{
    bytes.push_back(static_cast<std::byte>(value & 0xFFU));
    bytes.push_back(static_cast<std::byte>((value >> 8U) & 0xFFU));
}

void append_f32(std::vector<std::byte>& bytes, const float value)
{
    const auto bits = std::bit_cast<std::uint32_t>(value);
    for (std::uint32_t shift = 0; shift < 32U; shift += 8U)
    {
        bytes.push_back(static_cast<std::byte>((bits >> shift) & 0xFFU));
    }
}

[[nodiscard]] std::array<float, 3> to_gltf(const Vec3& value) noexcept
{
    return {value.y, value.z, value.x};
}

[[nodiscard]] std::optional<std::array<float, 3>> normalized_gltf(const Vec3& value) noexcept
{
    const auto mapped = to_gltf(value);
    const auto length =
        std::sqrt((mapped[0] * mapped[0]) + (mapped[1] * mapped[1]) + (mapped[2] * mapped[2]));
    if (!std::isfinite(length) || length <= std::numeric_limits<float>::epsilon())
    {
        return std::nullopt;
    }
    return std::array<float, 3>{mapped[0] / length, mapped[1] / length, mapped[2] / length};
}

template <typename Writer>
[[nodiscard]] ByteRange append_range(std::vector<std::byte>& bytes, Writer writer)
{
    align_four(bytes);
    const auto offset = bytes.size();
    writer();
    return {.offset = offset, .size = bytes.size() - offset};
}

[[nodiscard]] StaticMeshResult<BinaryLayout> build_binary(const StaticMeshBinding& binding)
{
    BinaryLayout layout;
    layout.minimum.fill(std::numeric_limits<float>::max());
    layout.maximum.fill(std::numeric_limits<float>::lowest());
    layout.positions =
        append_range(layout.bytes,
                     [&]
                     {
                         for (const auto& source : binding.mesh.positions)
                         {
                             const auto value = to_gltf(source);
                             for (std::size_t component = 0; component < value.size(); ++component)
                             {
                                 append_f32(layout.bytes, value[component]);
                                 layout.minimum[component] =
                                     std::min(layout.minimum[component], value[component]);
                                 layout.maximum[component] =
                                     std::max(layout.maximum[component], value[component]);
                             }
                         }
                     });
    bool normals_valid = true;
    layout.normals = append_range(layout.bytes,
                                  [&]
                                  {
                                      for (const auto& source : binding.mesh.normals)
                                      {
                                          const auto value = normalized_gltf(source);
                                          normals_valid = normals_valid && value.has_value();
                                          if (value.has_value())
                                          {
                                              for (const float component : *value)
                                              {
                                                  append_f32(layout.bytes, component);
                                              }
                                          }
                                      }
                                  });
    if (!normals_valid)
    {
        return StaticMeshResult<BinaryLayout>::failure(gltf_error("gltf.normal"));
    }
    layout.uv0 = append_range(layout.bytes,
                              [&]
                              {
                                  for (const auto& value : binding.mesh.uv0)
                                  {
                                      append_f32(layout.bytes, value.u);
                                      append_f32(layout.bytes, value.v);
                                  }
                              });
    if (binding.mesh.uv1_field_present)
    {
        layout.uv1 = append_range(layout.bytes,
                                  [&]
                                  {
                                      for (const auto& value : binding.mesh.uv1)
                                      {
                                          append_f32(layout.bytes, value.u);
                                          append_f32(layout.bytes, value.v);
                                      }
                                  });
    }
    layout.indices = append_range(layout.bytes,
                                  [&]
                                  {
                                      for (const auto index : binding.mesh.indices)
                                      {
                                          append_u16(layout.bytes, index);
                                      }
                                  });
    return StaticMeshResult<BinaryLayout>::success(std::move(layout));
}

void write_range(std::ostringstream& output, const ByteRange range, const int target)
{
    output << R"({"buffer": 0, "byteOffset": )" << range.offset << R"(, "byteLength": )"
           << range.size << R"(, "target": )" << target << '}';
}

void write_vec3(std::ostringstream& output, const std::array<float, 3>& value)
{
    output << '[' << value[0] << ", " << value[1] << ", " << value[2] << ']';
}

void write_buffer_views(std::ostringstream& output, const BinaryLayout& layout)
{
    output << "  \"bufferViews\": [\n    ";
    write_range(output, layout.positions, 34962);
    output << ",\n    ";
    write_range(output, layout.normals, 34962);
    output << ",\n    ";
    write_range(output, layout.uv0, 34962);
    if (layout.uv1.has_value())
    {
        output << ",\n    ";
        write_range(output, *layout.uv1, 34962);
    }
    output << ",\n    ";
    write_range(output, layout.indices, 34963);
    output << "\n  ],\n";
}

void write_accessors(std::ostringstream& output, const StaticMeshBinding& binding,
                     const BinaryLayout& layout)
{
    const auto vertex_count = binding.mesh.positions.size();
    const auto index_view = layout.uv1.has_value() ? 4U : 3U;
    output << "  \"accessors\": [\n"
           << R"(    {"bufferView": 0, "componentType": 5126, "count": )" << vertex_count
           << R"(, "type": "VEC3", "min": )";
    write_vec3(output, layout.minimum);
    output << R"(, "max": )";
    write_vec3(output, layout.maximum);
    output << "},\n"
           << R"(    {"bufferView": 1, "componentType": 5126, "count": )" << vertex_count
           << R"(, "type": "VEC3"},)" << '\n'
           << R"(    {"bufferView": 2, "componentType": 5126, "count": )" << vertex_count
           << R"(, "type": "VEC2"})";
    if (layout.uv1.has_value())
    {
        output << ",\n"
               << R"(    {"bufferView": 3, "componentType": 5126, "count": )" << vertex_count
               << R"(, "type": "VEC2"})";
    }
    for (const auto& section : binding.mesh.sections)
    {
        output << ",\n"
               << R"(    {"bufferView": )" << index_view << R"(, "byteOffset": )"
               << section.first_index * 2U << R"(, "componentType": 5123, "count": )"
               << section.triangle_count * 3U << R"(, "type": "SCALAR"})";
    }
    output << "\n  ],\n";
}

void write_materials(std::ostringstream& output, const StaticMeshBinding& binding)
{
    output << "  \"materials\": [\n";
    for (std::size_t index = 0; index < binding.mesh.sections.size(); ++index)
    {
        output << R"(    {"name": )"
               << json_string(binding.package.descriptor.material_object_names[index])
               << R"(, "doubleSided": )"
               << (binding.mesh.sections[index].two_sided ? "true" : "false")
               << R"(, "extras": {"tmxyMaterialSlot": )" << index << "}}"
               << (index + 1U == binding.mesh.sections.size() ? "\n" : ",\n");
    }
    output << "  ],\n";
}

void write_primitives(std::ostringstream& output, const StaticMeshBinding& binding,
                      const bool has_uv1)
{
    const auto first_index_accessor = has_uv1 ? 4U : 3U;
    output << R"(  "meshes": [{"name": )" << json_string(binding.package.object_name_bytes)
           << R"(, "primitives": [)" << '\n';
    for (std::size_t index = 0; index < binding.mesh.sections.size(); ++index)
    {
        output << R"(    {"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2)";
        if (has_uv1)
        {
            output << R"(, "TEXCOORD_1": 3)";
        }
        output << R"(}, "indices": )" << first_index_accessor + index << R"(, "material": )"
               << index << R"(, "mode": 4})"
               << (index + 1U == binding.mesh.sections.size() ? "\n" : ",\n");
    }
    output << "  ]}],\n";
}

[[nodiscard]] std::string build_json(const StaticMeshBinding& binding, const BinaryLayout& layout,
                                     const std::string_view buffer_uri)
{
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<float>::max_digits10) << "{\n"
           << R"(  "asset": {"version": "2.0", "generator": "TMXY.StaticMesh 0.1.0"},)" << '\n'
           << R"(  "scene": 0,)" << '\n'
           << R"(  "scenes": [{"nodes": [0]}],)" << '\n'
           << R"(  "nodes": [{"mesh": 0, "name": )"
           << json_string(binding.package.object_name_bytes) << "}],\n"
           << R"(  "buffers": [{"uri": )" << json_string(buffer_uri) << R"(, "byteLength": )"
           << layout.bytes.size() << "}],\n";
    write_buffer_views(output, layout);
    write_accessors(output, binding, layout);
    write_materials(output, binding);
    write_primitives(output, binding, layout.uv1.has_value());
    output
        << R"tmxy(  "extras": {"tmxyCoordinateMapping": "legacy(x,y,z)-to-gltf(y,z,x)", "tmxyWinding": "preserved"})tmxy"
        << '\n'
        << "}\n";
    return output.str();
}

} // namespace

StaticMeshResult<GltfArtifacts> build_gltf2(const StaticMeshBinding& binding,
                                            const std::string_view buffer_uri)
{
    if (!is_safe_buffer_uri(buffer_uri))
    {
        return StaticMeshResult<GltfArtifacts>::failure(gltf_error("gltf.buffer_uri"));
    }
    auto layout = build_binary(binding);
    if (!layout.has_value())
    {
        return StaticMeshResult<GltfArtifacts>::failure(layout.error());
    }
    auto value = std::move(layout).take_value();
    GltfArtifacts result;
    result.json = build_json(binding, value, buffer_uri);
    result.binary = std::move(value.bytes);
    return StaticMeshResult<GltfArtifacts>::success(std::move(result));
}

} // namespace tmxy::static_mesh
