#include "tmxy/package/package_inventory.hpp"

#include "tmxy/package/package_v1.hpp"
#include "tmxy/package/package_v1_reader.hpp"
#include "tmxy/package/package_v2.hpp"
#include "tmxy/package/package_v2_reader.hpp"
#include "tmxy/package/package_v3.hpp"
#include "tmxy/package/package_v3_reader.hpp"

#include <iomanip>
#include <sstream>
#include <string_view>
#include <unordered_set>

namespace tmxy::package
{

namespace
{

[[nodiscard]] bool has_version(const std::span<const std::byte> bytes,
                               const std::string_view version)
{
    if (bytes.size() < 2U + version.size())
    {
        return false;
    }
    const auto length = static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[0])) |
                        (static_cast<std::size_t>(std::to_integer<std::uint8_t>(bytes[1])) << 8U);
    if (length != version.size())
    {
        return false;
    }
    for (std::size_t index = 0; index < length; ++index)
    {
        if (std::to_integer<unsigned char>(bytes[index + 2U]) !=
            static_cast<unsigned char>(version[index]))
        {
            return false;
        }
    }
    return true;
}

template <typename Record>
[[nodiscard]] std::uint64_t count_classes(const std::vector<Record>& records)
{
    std::unordered_set<std::string> classes;
    classes.reserve(records.size());
    for (const auto& record : records)
    {
        classes.insert(record.class_name_bytes);
    }
    return classes.size();
}

} // namespace

PackageInventory inspect_package(const std::span<const std::byte> bytes)
{
    PackageInventory inventory;
    inventory.file_bytes = bytes.size();
    if (bytes.empty())
    {
        inventory.version = "empty";
        inventory.error = "empty_file";
        return inventory;
    }

    if (has_version(bytes, kPackageV1Version))
    {
        inventory.version = "1.0";
        inventory.recognized = true;
        const auto result = PackageV1Reader{}.parse(bytes);
        if (!result.has_value())
        {
            inventory.error = std::string(to_string(result.error().code));
            inventory.error_offset = result.error().absolute_offset;
            return inventory;
        }
        const auto& header = result.value();
        inventory.parsed = true;
        inventory.directory_bytes = header.header_size;
        inventory.record_count = header.records.size();
        inventory.distinct_class_count = count_classes(header.records);
        inventory.unknown_object_count = header.records.size();
        inventory.metadata_fingerprint = package_v1_metadata_fingerprint(header);
        inventory.error = "none";
        return inventory;
    }
    if (has_version(bytes, kPackageV2Version))
    {
        inventory.version = "2.0";
        inventory.recognized = true;
        const auto result = PackageV2Reader{}.parse(bytes);
        if (!result.has_value())
        {
            inventory.error = std::string(to_string(result.error().code));
            inventory.error_offset = result.error().absolute_offset;
            return inventory;
        }
        const auto& header = result.value();
        inventory.parsed = true;
        inventory.directory_bytes = header.directory_size;
        inventory.record_count = header.records.size();
        inventory.distinct_class_count = count_classes(header.records);
        inventory.unknown_object_count = header.records.size();
        inventory.metadata_fingerprint = package_v2_metadata_fingerprint(header);
        inventory.error = "none";
        return inventory;
    }
    if (has_version(bytes, kPackageV3Version))
    {
        inventory.version = "3.0";
        inventory.recognized = true;
        const auto result = PackageV3Reader{}.parse(bytes);
        if (!result.has_value())
        {
            inventory.error = std::string(to_string(result.error().code));
            inventory.error_offset = result.error().absolute_offset;
            return inventory;
        }
        const auto& header = result.value();
        inventory.parsed = true;
        inventory.directory_bytes = header.directory_size;
        inventory.record_count = header.records.size();
        inventory.distinct_class_count = count_classes(header.records);
        inventory.unknown_object_count = header.records.size();
        inventory.metadata_fingerprint = package_v3_metadata_fingerprint(header);
        inventory.error = "none";
        return inventory;
    }

    return inventory;
}

std::string package_inventory_to_json(const PackageInventory& inventory)
{
    std::ostringstream output;
    output << R"({"schema_version":1,"version":")" << inventory.version << R"(","recognized":)"
           << (inventory.recognized ? "true" : "false")
           << ",\"parsed\":" << (inventory.parsed ? "true" : "false")
           << ",\"file_bytes\":" << inventory.file_bytes
           << ",\"directory_bytes\":" << inventory.directory_bytes
           << ",\"record_count\":" << inventory.record_count
           << ",\"distinct_class_count\":" << inventory.distinct_class_count
           << ",\"unknown_object_count\":" << inventory.unknown_object_count
           << R"(,"metadata_fingerprint":")" << std::hex << std::setfill('0') << std::setw(16)
           << inventory.metadata_fingerprint << std::dec << R"(","error":")" << inventory.error
           << R"(","error_offset":)" << inventory.error_offset << '}';
    return output.str();
}

} // namespace tmxy::package
