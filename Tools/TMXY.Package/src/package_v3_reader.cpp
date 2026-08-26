#include "tmxy/package/package_v3_reader.hpp"

#include "tmxy/format/binary_reader.hpp"
#include "tmxy/package/package_directory_codec.hpp"

#include <algorithm>
#include <bit>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <unordered_set>
#include <utility>
#include <variant>
#include <vector>

namespace tmxy::package
{

namespace
{

template <typename Value> using StepResult = std::variant<Value, PackageV3Error>;

struct DirectoryContext final
{
    std::uint64_t file_offset{0};
    std::size_t size{0};
};

[[nodiscard]] PackageV3Error
make_error(const PackageV3ErrorCode code, const std::uint64_t absolute_offset, std::string context,
           const std::uint64_t record_index = PackageV3Error::kNoRecordIndex)
{
    return PackageV3Error{
        .code = code,
        .absolute_offset = absolute_offset,
        .record_index = record_index,
        .context = std::move(context),
        .read_error_code = std::nullopt,
    };
}

[[nodiscard]] PackageV3Error from_outer_read_error(const format::ReadError& error,
                                                   std::string context)
{
    return PackageV3Error{
        .code = PackageV3ErrorCode::read_failure,
        .absolute_offset = error.absolute_offset,
        .record_index = PackageV3Error::kNoRecordIndex,
        .context = std::move(context),
        .read_error_code = error.code,
    };
}

[[nodiscard]] std::uint64_t map_directory_offset(const DirectoryContext& directory,
                                                 const std::uint64_t decoded_offset) noexcept
{
    return map_package_directory_offset({
        .version = PackageDirectoryVersion::v3,
        .file_offset = directory.file_offset,
        .directory_size = directory.size,
        .decoded_offset = decoded_offset,
    });
}

[[nodiscard]] PackageV3Error from_directory_read_error(const format::ReadError& error,
                                                       const DirectoryContext& directory,
                                                       std::string context,
                                                       const std::uint64_t record_index)
{
    return PackageV3Error{
        .code = PackageV3ErrorCode::read_failure,
        .absolute_offset = map_directory_offset(directory, error.absolute_offset),
        .record_index = record_index,
        .context = std::move(context),
        .read_error_code = error.code,
    };
}

[[nodiscard]] StepResult<std::string> read_outer_string(format::BinaryReader& reader,
                                                        std::string context)
{
    const auto length = reader.read_u16();
    if (!length.has_value())
    {
        return from_outer_read_error(length.error(), std::move(context));
    }
    const auto bytes = reader.read_bytes(length.value());
    if (!bytes.has_value())
    {
        return from_outer_read_error(bytes.error(), std::move(context));
    }
    std::string value;
    value.reserve(bytes.value().size());
    for (const auto byte : bytes.value())
    {
        value.push_back(static_cast<char>(std::to_integer<unsigned char>(byte)));
    }
    return value;
}

[[nodiscard]] StepResult<std::string> read_directory_string(format::BinaryReader& reader,
                                                            const DirectoryContext& directory,
                                                            std::string context,
                                                            const std::uint64_t record_index)
{
    const auto length = reader.read_u16();
    if (!length.has_value())
    {
        return from_directory_read_error(length.error(), directory, std::move(context),
                                         record_index);
    }
    const auto bytes = reader.read_bytes(length.value());
    if (!bytes.has_value())
    {
        return from_directory_read_error(bytes.error(), directory, std::move(context),
                                         record_index);
    }
    std::string value;
    value.reserve(bytes.value().size());
    for (const auto byte : bytes.value())
    {
        value.push_back(static_cast<char>(std::to_integer<unsigned char>(byte)));
    }
    return value;
}

[[nodiscard]] StepResult<PackageV3ObjectRecord> read_record(format::BinaryReader& reader,
                                                            const DirectoryContext& directory,
                                                            const std::uint64_t record_index)
{
    auto name = read_directory_string(reader, directory, "package.objects.name", record_index);
    if (const auto* error = std::get_if<PackageV3Error>(&name))
    {
        return *error;
    }
    auto class_name =
        read_directory_string(reader, directory, "package.objects.class", record_index);
    if (const auto* error = std::get_if<PackageV3Error>(&class_name))
    {
        return *error;
    }

    const auto offset_position = reader.absolute_position();
    const auto offset = reader.read_i32();
    if (!offset.has_value())
    {
        return from_directory_read_error(offset.error(), directory, "package.objects.offset",
                                         record_index);
    }
    const auto size_position = reader.absolute_position();
    const auto size = reader.read_i32();
    if (!size.has_value())
    {
        return from_directory_read_error(size.error(), directory, "package.objects.size",
                                         record_index);
    }
    if (offset.value() < 0)
    {
        return make_error(PackageV3ErrorCode::negative_object_offset,
                          map_directory_offset(directory, offset_position),
                          "package.objects.offset", record_index);
    }
    if (size.value() < 0)
    {
        return make_error(PackageV3ErrorCode::negative_object_size,
                          map_directory_offset(directory, size_position), "package.objects.size",
                          record_index);
    }

    return PackageV3ObjectRecord{
        .name_bytes = std::get<std::string>(std::move(name)),
        .class_name_bytes = std::get<std::string>(std::move(class_name)),
        .offset = static_cast<std::uint64_t>(offset.value()),
        .size = static_cast<std::uint64_t>(size.value()),
    };
}

[[nodiscard]] std::optional<PackageV3Error> validate_ranges(const PackageV3Header& header)
{
    std::unordered_set<std::string> names;
    std::vector<const PackageV3ObjectRecord*> sorted;
    sorted.reserve(header.records.size());
    for (std::size_t index = 0; index < header.records.size(); ++index)
    {
        const auto& record = header.records[index];
        if (!names.insert(record.name_bytes).second)
        {
            return make_error(PackageV3ErrorCode::duplicate_object_name, record.offset,
                              "package.objects.name", static_cast<std::uint64_t>(index));
        }
        sorted.push_back(&record);
    }
    std::ranges::sort(sorted, {}, &PackageV3ObjectRecord::offset);

    std::uint64_t cursor = header.header_size;
    for (const auto* record : sorted)
    {
        const auto record_index = static_cast<std::uint64_t>(record - &header.records.front());
        if (record->offset != cursor)
        {
            return make_error(PackageV3ErrorCode::non_contiguous_object_range, record->offset,
                              "package.objects.range", record_index);
        }
        if (record->offset > header.file_size || record->size > header.file_size - record->offset)
        {
            return make_error(PackageV3ErrorCode::object_range_out_of_file, record->offset,
                              "package.objects.range", record_index);
        }
        cursor = record->offset + record->size;
    }
    if (cursor != header.file_size)
    {
        return make_error(PackageV3ErrorCode::non_contiguous_object_range, cursor,
                          "package.objects.range");
    }
    return std::nullopt;
}

} // namespace

PackageV3ParseResult PackageV3ParseResult::success(PackageV3Header header)
{
    return PackageV3ParseResult(std::move(header));
}

PackageV3ParseResult PackageV3ParseResult::failure(PackageV3Error error)
{
    return PackageV3ParseResult(std::move(error));
}

bool PackageV3ParseResult::has_value() const noexcept
{
    return std::holds_alternative<PackageV3Header>(storage_);
}

const PackageV3Header& PackageV3ParseResult::value() const& noexcept
{
    const auto* result = std::get_if<PackageV3Header>(&storage_);
    assert(result != nullptr);
    return *result;
}

const PackageV3Error& PackageV3ParseResult::error() const& noexcept
{
    const auto* result = std::get_if<PackageV3Error>(&storage_);
    assert(result != nullptr);
    return *result;
}

PackageV3ParseResult::PackageV3ParseResult(PackageV3Header header) : storage_(std::move(header)) {}

PackageV3ParseResult::PackageV3ParseResult(PackageV3Error error) : storage_(std::move(error)) {}

PackageV3Reader::PackageV3Reader(const PackageV3Limits limits) : limits_(limits) {}

PackageV3ParseResult PackageV3Reader::parse(const std::span<const std::byte> bytes) const
{
    format::BinaryReader outer(bytes, format::ByteOrder::little_endian, 0, "package-v3");
    auto version = read_outer_string(outer, "package.version");
    if (const auto* error = std::get_if<PackageV3Error>(&version))
    {
        return PackageV3ParseResult::failure(*error);
    }
    if (std::get<std::string>(version) != kPackageV3Version)
    {
        return PackageV3ParseResult::failure(
            make_error(PackageV3ErrorCode::invalid_version, 2, "package.version"));
    }

    const auto directory_size_position = outer.absolute_position();
    const auto directory_size = outer.read_i32();
    if (!directory_size.has_value())
    {
        return PackageV3ParseResult::failure(
            from_outer_read_error(directory_size.error(), "package.directory_size"));
    }
    if (directory_size.value() < 0)
    {
        return PackageV3ParseResult::failure(make_error(PackageV3ErrorCode::negative_directory_size,
                                                        directory_size_position,
                                                        "package.directory_size"));
    }
    const auto directory_bytes = static_cast<std::size_t>(directory_size.value());
    if (directory_bytes > limits_.maximum_directory_bytes)
    {
        return PackageV3ParseResult::failure(
            make_error(PackageV3ErrorCode::directory_size_limit_exceeded, directory_size_position,
                       "package.directory_size"));
    }
    if (directory_bytes < 18U)
    {
        return PackageV3ParseResult::failure(make_error(PackageV3ErrorCode::directory_too_small,
                                                        directory_size_position,
                                                        "package.directory_size"));
    }
    if (directory_bytes > outer.remaining())
    {
        return PackageV3ParseResult::failure(make_error(PackageV3ErrorCode::directory_out_of_file,
                                                        outer.absolute_position(),
                                                        "package.directory"));
    }

    const DirectoryContext directory{
        .file_offset = outer.absolute_position(),
        .size = directory_bytes,
    };
    const auto encoded = outer.read_bytes(directory_bytes);
    if (!encoded.has_value())
    {
        return PackageV3ParseResult::failure(
            from_outer_read_error(encoded.error(), "package.directory"));
    }
    const auto decoded = decode_package_directory(PackageDirectoryVersion::v3, encoded.value());
    for (std::size_t index = 0; index < kPackageV3DirectoryPrefix.size(); ++index)
    {
        if (decoded[index] != kPackageV3DirectoryPrefix[index])
        {
            return PackageV3ParseResult::failure(
                make_error(PackageV3ErrorCode::invalid_directory_prefix,
                           map_directory_offset(directory, index), "package.directory_prefix"));
        }
    }

    format::BinaryReader directory_reader(decoded, format::ByteOrder::little_endian, 0,
                                          "package-v3-directory");
    const auto seek = directory_reader.seek(kPackageV3DirectoryPrefix.size());
    if (!seek.has_value())
    {
        return PackageV3ParseResult::failure(from_directory_read_error(
            seek.error(), directory, "package.directory_prefix", PackageV3Error::kNoRecordIndex));
    }
    const auto count_position = directory_reader.absolute_position();
    const auto count = directory_reader.read_i32();
    if (!count.has_value())
    {
        return PackageV3ParseResult::failure(from_directory_read_error(
            count.error(), directory, "package.object_count", PackageV3Error::kNoRecordIndex));
    }
    if (count.value() < 0)
    {
        return PackageV3ParseResult::failure(
            make_error(PackageV3ErrorCode::negative_object_count,
                       map_directory_offset(directory, count_position), "package.object_count"));
    }
    const auto object_count = static_cast<std::size_t>(count.value());
    if (object_count > limits_.maximum_object_count)
    {
        return PackageV3ParseResult::failure(
            make_error(PackageV3ErrorCode::object_count_limit_exceeded,
                       map_directory_offset(directory, count_position), "package.object_count"));
    }
    constexpr std::size_t kMinimumRecordBytes = 12;
    if (object_count > directory_reader.remaining() / kMinimumRecordBytes)
    {
        return PackageV3ParseResult::failure(
            make_error(PackageV3ErrorCode::impossible_object_count,
                       map_directory_offset(directory, count_position), "package.object_count"));
    }

    PackageV3Header header{
        .version = std::get<std::string>(std::move(version)),
        .records = {},
        .directory_offset = directory.file_offset,
        .directory_size = directory.size,
        .header_size = outer.absolute_position(),
        .file_size = bytes.size(),
    };
    header.records.reserve(object_count);
    for (std::size_t index = 0; index < object_count; ++index)
    {
        auto record = read_record(directory_reader, directory, static_cast<std::uint64_t>(index));
        if (const auto* error = std::get_if<PackageV3Error>(&record))
        {
            return PackageV3ParseResult::failure(*error);
        }
        header.records.push_back(std::get<PackageV3ObjectRecord>(std::move(record)));
    }
    if (directory_reader.remaining() != 0U)
    {
        return PackageV3ParseResult::failure(
            make_error(PackageV3ErrorCode::directory_trailing_bytes,
                       map_directory_offset(directory, directory_reader.absolute_position()),
                       "package.directory"));
    }
    if (const auto error = validate_ranges(header))
    {
        return PackageV3ParseResult::failure(*error);
    }
    return PackageV3ParseResult::success(std::move(header));
}

} // namespace tmxy::package
