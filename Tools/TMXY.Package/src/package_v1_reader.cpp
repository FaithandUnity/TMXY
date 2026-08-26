#include "tmxy/package/package_v1_reader.hpp"

#include "tmxy/format/binary_reader.hpp"

#include <algorithm>
#include <bit>
#include <cassert>
#include <string>
#include <unordered_set>
#include <utility>
#include <variant>

namespace tmxy::package
{

namespace
{

template <typename T> using StepResult = std::variant<T, PackageV1Error>;

[[nodiscard]] PackageV1Error from_read_error(const format::ReadError& error, std::string context,
                                             const std::uint64_t record_index)
{
    return PackageV1Error{
        .code = PackageV1ErrorCode::read_failure,
        .absolute_offset = error.absolute_offset,
        .record_index = record_index,
        .context = std::move(context),
        .read_error_code = error.code,
    };
}

[[nodiscard]] PackageV1Error
make_validation_error(const PackageV1ErrorCode code, const std::uint64_t absolute_offset,
                      std::string context,
                      const std::uint64_t record_index = PackageV1Error::kNoRecordIndex)
{
    return PackageV1Error{
        .code = code,
        .absolute_offset = absolute_offset,
        .record_index = record_index,
        .context = std::move(context),
        .read_error_code = std::nullopt,
    };
}

[[nodiscard]] StepResult<std::string> read_legacy_string(format::BinaryReader& reader,
                                                         std::string context,
                                                         const std::uint64_t record_index)
{
    const auto length = reader.read_u16();
    if (!length.has_value())
    {
        return from_read_error(length.error(), std::move(context), record_index);
    }
    const auto bytes = reader.read_bytes(length.value());
    if (!bytes.has_value())
    {
        return from_read_error(bytes.error(), std::move(context), record_index);
    }

    std::string value;
    value.reserve(bytes.value().size());
    for (const auto byte : bytes.value())
    {
        value.push_back(std::bit_cast<char>(std::to_integer<unsigned char>(byte)));
    }
    return value;
}

[[nodiscard]] StepResult<PackageV1ObjectRecord> read_record(format::BinaryReader& reader,
                                                            const std::uint64_t record_index)
{
    auto name = read_legacy_string(reader, "package.objects.name", record_index);
    if (const auto* error = std::get_if<PackageV1Error>(&name))
    {
        return *error;
    }
    auto class_name = read_legacy_string(reader, "package.objects.class", record_index);
    if (const auto* error = std::get_if<PackageV1Error>(&class_name))
    {
        return *error;
    }

    const auto offset_position = reader.absolute_position();
    const auto offset = reader.read_i32();
    if (!offset.has_value())
    {
        return from_read_error(offset.error(), "package.objects.offset", record_index);
    }
    const auto size_position = reader.absolute_position();
    const auto size = reader.read_i32();
    if (!size.has_value())
    {
        return from_read_error(size.error(), "package.objects.size", record_index);
    }
    if (offset.value() < 0)
    {
        return make_validation_error(PackageV1ErrorCode::negative_object_offset, offset_position,
                                     "package.objects.offset", record_index);
    }
    if (size.value() < 0)
    {
        return make_validation_error(PackageV1ErrorCode::negative_object_size, size_position,
                                     "package.objects.size", record_index);
    }

    return PackageV1ObjectRecord{
        .name_bytes = std::get<std::string>(std::move(name)),
        .class_name_bytes = std::get<std::string>(std::move(class_name)),
        .offset = static_cast<std::uint64_t>(offset.value()),
        .size = static_cast<std::uint64_t>(size.value()),
    };
}

[[nodiscard]] std::optional<PackageV1Error> validate_ranges(const PackageV1Header& header)
{
    std::unordered_set<std::string> names;
    std::vector<const PackageV1ObjectRecord*> sorted;
    sorted.reserve(header.records.size());
    for (std::size_t index = 0; index < header.records.size(); ++index)
    {
        const auto& record = header.records[index];
        if (!names.insert(record.name_bytes).second)
        {
            return make_validation_error(PackageV1ErrorCode::duplicate_object_name, record.offset,
                                         "package.objects.name", static_cast<std::uint64_t>(index));
        }
        sorted.push_back(&record);
    }
    std::ranges::sort(sorted, {}, &PackageV1ObjectRecord::offset);

    std::uint64_t cursor = header.header_size;
    for (const auto* record : sorted)
    {
        const auto record_index = static_cast<std::uint64_t>(record - &header.records.front());
        if (record->offset != cursor)
        {
            return make_validation_error(PackageV1ErrorCode::non_contiguous_object_range,
                                         record->offset, "package.objects.range", record_index);
        }
        if (record->offset > header.file_size || record->size > header.file_size - record->offset)
        {
            return make_validation_error(PackageV1ErrorCode::object_range_out_of_file,
                                         record->offset, "package.objects.range", record_index);
        }
        cursor = record->offset + record->size;
    }
    if (cursor != header.file_size)
    {
        return make_validation_error(PackageV1ErrorCode::non_contiguous_object_range, cursor,
                                     "package.objects.range");
    }
    return std::nullopt;
}

} // namespace

PackageV1ParseResult PackageV1ParseResult::success(PackageV1Header header)
{
    return PackageV1ParseResult(std::move(header));
}

PackageV1ParseResult PackageV1ParseResult::failure(PackageV1Error error)
{
    return PackageV1ParseResult(std::move(error));
}

bool PackageV1ParseResult::has_value() const noexcept
{
    return std::holds_alternative<PackageV1Header>(storage_);
}

const PackageV1Header& PackageV1ParseResult::value() const& noexcept
{
    const auto* result = std::get_if<PackageV1Header>(&storage_);
    assert(result != nullptr);
    return *result;
}

const PackageV1Error& PackageV1ParseResult::error() const& noexcept
{
    const auto* result = std::get_if<PackageV1Error>(&storage_);
    assert(result != nullptr);
    return *result;
}

PackageV1ParseResult::PackageV1ParseResult(PackageV1Header header) : storage_(std::move(header)) {}

PackageV1ParseResult::PackageV1ParseResult(PackageV1Error error) : storage_(std::move(error)) {}

PackageV1Reader::PackageV1Reader(const PackageV1Limits limits) : limits_(limits) {}

PackageV1ParseResult PackageV1Reader::parse(const std::span<const std::byte> bytes) const
{
    format::BinaryReader reader(bytes, format::ByteOrder::little_endian, 0, "package-v1");
    auto version = read_legacy_string(reader, "package.version", PackageV1Error::kNoRecordIndex);
    if (const auto* error = std::get_if<PackageV1Error>(&version))
    {
        return PackageV1ParseResult::failure(*error);
    }
    if (std::get<std::string>(version) != kPackageV1Version)
    {
        return PackageV1ParseResult::failure(
            make_validation_error(PackageV1ErrorCode::invalid_version, 2, "package.version"));
    }

    const auto count_position = reader.absolute_position();
    const auto count = reader.read_i32();
    if (!count.has_value())
    {
        return PackageV1ParseResult::failure(
            from_read_error(count.error(), "package.object_count", PackageV1Error::kNoRecordIndex));
    }
    if (count.value() < 0)
    {
        return PackageV1ParseResult::failure(make_validation_error(
            PackageV1ErrorCode::negative_object_count, count_position, "package.object_count"));
    }
    const auto object_count = static_cast<std::size_t>(count.value());
    if (object_count > limits_.maximum_object_count)
    {
        return PackageV1ParseResult::failure(
            make_validation_error(PackageV1ErrorCode::object_count_limit_exceeded, count_position,
                                  "package.object_count"));
    }
    constexpr std::size_t kMinimumRecordBytes = 12;
    if (object_count > reader.remaining() / kMinimumRecordBytes)
    {
        return PackageV1ParseResult::failure(make_validation_error(
            PackageV1ErrorCode::impossible_object_count, count_position, "package.object_count"));
    }

    PackageV1Header header;
    header.version = std::get<std::string>(std::move(version));
    header.file_size = static_cast<std::uint64_t>(bytes.size());
    header.records.reserve(object_count);
    for (std::size_t index = 0; index < object_count; ++index)
    {
        auto record = read_record(reader, static_cast<std::uint64_t>(index));
        if (const auto* error = std::get_if<PackageV1Error>(&record))
        {
            return PackageV1ParseResult::failure(*error);
        }
        header.records.push_back(std::get<PackageV1ObjectRecord>(std::move(record)));
    }
    header.header_size = reader.absolute_position();
    if (const auto error = validate_ranges(header))
    {
        return PackageV1ParseResult::failure(*error);
    }
    return PackageV1ParseResult::success(std::move(header));
}

} // namespace tmxy::package
