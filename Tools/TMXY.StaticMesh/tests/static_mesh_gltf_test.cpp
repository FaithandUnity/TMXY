#include "tmxy/static_mesh/static_mesh_gltf.hpp"

#include <array>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <string_view>

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

[[nodiscard]] float read_f32(const std::vector<std::byte>& bytes, const std::size_t offset)
{
    if (offset + 4U > bytes.size())
    {
        return 0.0F;
    }
    std::uint32_t bits = 0;
    for (std::uint32_t index = 0; index < 4U; ++index)
    {
        bits |= static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[offset + index]))
                << (index * 8U);
    }
    return std::bit_cast<float>(bits);
}

[[nodiscard]] tmxy::static_mesh::StaticMeshBinding make_binding()
{
    using namespace tmxy::static_mesh;
    StaticMeshBinding binding;
    binding.mesh.positions = {
        {.x = 1.0F, .y = 2.0F, .z = 3.0F},
        {.x = 2.0F, .y = 2.0F, .z = 3.0F},
        {.x = 2.0F, .y = 4.0F, .z = 3.0F},
        {.x = 1.0F, .y = 4.0F, .z = 3.0F},
    };
    binding.mesh.normals.assign(4, {.x = 0.0F, .y = 0.0F, .z = 2.0F});
    binding.mesh.uv0 = {{.u = 0.0F, .v = 0.0F},
                        {.u = 1.0F, .v = 0.0F},
                        {.u = 1.0F, .v = 1.0F},
                        {.u = 0.0F, .v = 1.0F}};
    binding.mesh.uv1_field_present = true;
    binding.mesh.uv1 = {{.u = 0.25F, .v = 0.25F},
                        {.u = 0.75F, .v = 0.25F},
                        {.u = 0.75F, .v = 0.75F},
                        {.u = 0.25F, .v = 0.75F}};
    binding.mesh.indices = {0, 1, 2, 0, 2, 3};
    binding.mesh.sections = {
        {.triangle_count = 1,
         .minimum_vertex_index = 0,
         .maximum_vertex_index = 2,
         .two_sided = false,
         .first_index = 0},
        {.triangle_count = 1,
         .minimum_vertex_index = 0,
         .maximum_vertex_index = 3,
         .two_sided = true,
         .first_index = 3},
    };
    binding.package.object_name_bytes = "fixture.mesh";
    binding.package.descriptor.material_object_names = {"material.slot0", "material.slot1"};
    binding.material_slot_resolution = {.declared_material_slot_count = 2,
                                        .effective_material_slot_count = 2,
                                        .ignored_material_slot_count = 0,
                                        .basis = MaterialSlotBasis::package_descriptor};
    return binding;
}

} // namespace

int main()
{
    TestContext test;
    const auto binding = make_binding();
    const auto first = tmxy::static_mesh::build_gltf2(binding, "fixture.bin");
    const auto second = tmxy::static_mesh::build_gltf2(binding, "fixture.bin");
    test.expect(first.has_value() && second.has_value(), "valid mesh must export to glTF");
    if (!first.has_value() || !second.has_value())
    {
        return test.failures();
    }
    test.expect(first.value().json == second.value().json &&
                    first.value().binary == second.value().binary,
                "glTF export must be deterministic");
    test.expect(first.value().binary.size() == 172U, "glTF buffer layout changed");
    test.expect(read_f32(first.value().binary, 0) == 2.0F &&
                    read_f32(first.value().binary, 4) == 3.0F &&
                    read_f32(first.value().binary, 8) == 1.0F,
                "legacy-to-glTF cyclic coordinate mapping changed");
    test.expect(first.value().json.find(R"("version": "2.0")") != std::string::npos,
                "glTF asset version is missing");
    test.expect(first.value().json.find(R"("TEXCOORD_1": 3)") != std::string::npos,
                "second UV channel is missing");
    test.expect(first.value().json.find(R"("byteOffset": 6, "componentType": 5123)") !=
                    std::string::npos,
                "second material section index range is missing");
    test.expect(first.value().json.find(R"("name": "material.slot1", "doubleSided": true)") !=
                    std::string::npos,
                "material order or two-sided policy changed");
    test.expect(!tmxy::static_mesh::build_gltf2(binding, "../escape.bin").has_value(),
                "unsafe buffer URI must be rejected");
    return test.failures();
}
