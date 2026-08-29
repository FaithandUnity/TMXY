#pragma once

#include <string>

namespace tmxy::animation
{
struct PackageAnimationSetDescriptor;
}

namespace tmxy::skeletal_mesh
{
struct SkeletalMeshDescriptor;
}

namespace tmxy::static_mesh
{
struct StaticMeshDescriptor;
}

namespace tmxy::texture
{
struct TextureDescriptor;
}

namespace tmxy::asset_inventory
{

// Returns a versioned binary canonical representation, not printable text or a digest.
// Length prefixes make variable-width fields unambiguous. Storage-only offsets and sizes
// are deliberately omitted; every descriptor field retained for conversion is included.
[[nodiscard]] std::string semantic_signature(const texture::TextureDescriptor& descriptor);
[[nodiscard]] std::string semantic_signature(const static_mesh::StaticMeshDescriptor& descriptor);
[[nodiscard]] std::string
semantic_signature(const skeletal_mesh::SkeletalMeshDescriptor& descriptor);
[[nodiscard]] std::string
semantic_signature(const animation::PackageAnimationSetDescriptor& descriptor);

// Exercises field sensitivity, sequence ordering, optional-state encoding, float bit
// preservation, variable-width field separation, and storage-location independence.
[[nodiscard]] bool semantic_signature_self_test();

} // namespace tmxy::asset_inventory
