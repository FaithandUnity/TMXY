#include "tmxy/package/package_normalized_tree.hpp"

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace tmxy::package
{

namespace
{

template <typename Header>
[[nodiscard]] NormalizedPackageTree normalize_impl(const Header& header, std::string&& source_label,
                                                   const std::uint64_t directory_offset,
                                                   const std::uint64_t directory_size)
{
    NormalizedPackageTree tree{
        .source_label = std::move(source_label),
        .format_version = header.version,
        .file_size = header.file_size,
        .header_size = header.header_size,
        .directory_offset = directory_offset,
        .directory_size = directory_size,
        .objects = {},
    };
    tree.objects.reserve(header.records.size());
    for (std::size_t index = 0; index < header.records.size(); ++index)
    {
        const auto& record = header.records[index];
        tree.objects.push_back(NormalizedPackageObject{
            .index = index,
            .name_bytes = record.name_bytes,
            .class_name_bytes = record.class_name_bytes,
            .body_offset = record.offset,
            .body_size = record.size,
        });
    }
    return tree;
}

[[nodiscard]] char hex_digit(const std::uint8_t value) noexcept
{
    constexpr std::string_view kDigits = "0123456789abcdef";
    return kDigits[value & 0x0FU];
}

void append_json_string(std::string& output, const std::string_view value)
{
    output.push_back('"');
    for (const char character : value)
    {
        const auto byte = static_cast<unsigned char>(character);
        switch (byte)
        {
        case '"':
            output += "\\\"";
            break;
        case '\\':
            output += "\\\\";
            break;
        case '\b':
            output += "\\b";
            break;
        case '\f':
            output += "\\f";
            break;
        case '\n':
            output += "\\n";
            break;
        case '\r':
            output += "\\r";
            break;
        case '\t':
            output += "\\t";
            break;
        default:
            if (byte < 0x20U)
            {
                output += "\\u00";
                output.push_back(hex_digit(static_cast<std::uint8_t>(byte >> 4U)));
                output.push_back(hex_digit(byte));
            }
            else
            {
                output.push_back(static_cast<char>(byte));
            }
            break;
        }
    }
    output.push_back('"');
}

void append_hex(std::string& output, const std::string_view bytes)
{
    output.push_back('"');
    for (const char character : bytes)
    {
        const auto byte = static_cast<unsigned char>(character);
        output.push_back(hex_digit(static_cast<std::uint8_t>(byte >> 4U)));
        output.push_back(hex_digit(byte));
    }
    output.push_back('"');
}

void append_opaque_bytes(std::string& output, const std::string_view bytes)
{
    output += R"({"encoding":"opaque-bytes","hex":)";
    append_hex(output, bytes);
    output.push_back('}');
}

void append_unparsed_semantics(std::string& output)
{
    output += R"(,"references":{"state":"unparsed","items":[]})";
    output += R"(,"transform":{"state":"unparsed","matrix":null})";
    output += R"(,"materials":{"state":"unparsed","slots":[]})";
}

void append_object(std::string& output, const NormalizedPackageObject& object)
{
    output += R"({"index":)";
    output += std::to_string(object.index);
    output += R"(,"name":)";
    append_opaque_bytes(output, object.name_bytes);
    output += R"(,"class_name":)";
    append_opaque_bytes(output, object.class_name_bytes);
    output += R"(,"body":{"offset":)";
    output += std::to_string(object.body_offset);
    output += R"(,"size":)";
    output += std::to_string(object.body_size);
    output.push_back('}');
    append_unparsed_semantics(output);
    output += R"(,"unknown_fields":[{"kind":"object-body","offset":)";
    output += std::to_string(object.body_offset);
    output += R"(,"size":)";
    output += std::to_string(object.body_size);
    output += R"(,"preservation":"source-span"}]})";
}

} // namespace

NormalizedPackageTree normalize_package_tree(const PackageV1Header& header,
                                             std::string source_label)
{
    return normalize_impl(header, std::move(source_label), 0, header.header_size);
}

NormalizedPackageTree normalize_package_tree(const PackageV2Header& header,
                                             std::string source_label)
{
    return normalize_impl(header, std::move(source_label), header.directory_offset,
                          header.directory_size);
}

NormalizedPackageTree normalize_package_tree(const PackageV3Header& header,
                                             std::string source_label)
{
    return normalize_impl(header, std::move(source_label), header.directory_offset,
                          header.directory_size);
}

std::string package_tree_to_json(const NormalizedPackageTree& tree)
{
    std::string output;
    output.reserve(256U + (tree.objects.size() * 320U));
    output += R"({"schema":"tmxy.package.tree","schema_version":1,"source":{"label":)";
    append_json_string(output, tree.source_label);
    output += R"(,"file_size":)";
    output += std::to_string(tree.file_size);
    output += R"(},"package":{"format_version":)";
    append_json_string(output, tree.format_version);
    output += R"(,"header_size":)";
    output += std::to_string(tree.header_size);
    output += R"(,"directory":{"offset":)";
    output += std::to_string(tree.directory_offset);
    output += R"(,"size":)";
    output += std::to_string(tree.directory_size);
    output += R"(}},"objects":[)";
    for (std::size_t index = 0; index < tree.objects.size(); ++index)
    {
        if (index != 0U)
        {
            output.push_back(',');
        }
        append_object(output, tree.objects[index]);
    }
    output += "]}";
    return output;
}

} // namespace tmxy::package
