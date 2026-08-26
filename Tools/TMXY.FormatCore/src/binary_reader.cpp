#include "tmxy/format/binary_reader.hpp"

#include <bit>
#include <limits>

namespace tmxy::format
{

namespace
{

[[nodiscard]] std::uint64_t as_u64(const std::size_t value) noexcept
{
    static_assert(sizeof(std::size_t) <= sizeof(std::uint64_t));
    return static_cast<std::uint64_t>(value);
}

} // namespace

BinaryReader::BinaryReader(const std::span<const std::byte> bytes, const ByteOrder byte_order,
                           const std::uint64_t base_offset, std::string context)
    : bytes_(bytes), byte_order_(byte_order), base_offset_(base_offset),
      context_(std::move(context)),
      offset_range_valid_(as_u64(bytes.size()) <=
                          std::numeric_limits<std::uint64_t>::max() - base_offset)
{
}

std::size_t BinaryReader::size() const noexcept
{
    return bytes_.size();
}

std::size_t BinaryReader::position() const noexcept
{
    return position_;
}

std::size_t BinaryReader::remaining() const noexcept
{
    return bytes_.size() - position_;
}

std::uint64_t BinaryReader::absolute_position() const noexcept
{
    if (!offset_range_valid_)
    {
        return base_offset_;
    }
    return base_offset_ + as_u64(position_);
}

std::string_view BinaryReader::context() const noexcept
{
    return context_;
}

bool BinaryReader::offset_range_valid() const noexcept
{
    return offset_range_valid_;
}

ReadResult<std::uint8_t> BinaryReader::read_u8()
{
    auto result = read_unsigned(sizeof(std::uint8_t));
    if (!result.has_value())
    {
        return ReadResult<std::uint8_t>::failure(result.error());
    }
    return ReadResult<std::uint8_t>::success(static_cast<std::uint8_t>(result.value()));
}

ReadResult<std::uint16_t> BinaryReader::read_u16()
{
    auto result = read_unsigned(sizeof(std::uint16_t));
    if (!result.has_value())
    {
        return ReadResult<std::uint16_t>::failure(result.error());
    }
    return ReadResult<std::uint16_t>::success(static_cast<std::uint16_t>(result.value()));
}

ReadResult<std::uint32_t> BinaryReader::read_u32()
{
    auto result = read_unsigned(sizeof(std::uint32_t));
    if (!result.has_value())
    {
        return ReadResult<std::uint32_t>::failure(result.error());
    }
    return ReadResult<std::uint32_t>::success(static_cast<std::uint32_t>(result.value()));
}

ReadResult<std::uint64_t> BinaryReader::read_u64()
{
    return read_unsigned(sizeof(std::uint64_t));
}

ReadResult<std::int8_t> BinaryReader::read_i8()
{
    auto result = read_u8();
    if (!result.has_value())
    {
        return ReadResult<std::int8_t>::failure(result.error());
    }
    return ReadResult<std::int8_t>::success(std::bit_cast<std::int8_t>(result.value()));
}

ReadResult<std::int16_t> BinaryReader::read_i16()
{
    auto result = read_u16();
    if (!result.has_value())
    {
        return ReadResult<std::int16_t>::failure(result.error());
    }
    return ReadResult<std::int16_t>::success(std::bit_cast<std::int16_t>(result.value()));
}

ReadResult<std::int32_t> BinaryReader::read_i32()
{
    auto result = read_u32();
    if (!result.has_value())
    {
        return ReadResult<std::int32_t>::failure(result.error());
    }
    return ReadResult<std::int32_t>::success(std::bit_cast<std::int32_t>(result.value()));
}

ReadResult<std::int64_t> BinaryReader::read_i64()
{
    auto result = read_u64();
    if (!result.has_value())
    {
        return ReadResult<std::int64_t>::failure(result.error());
    }
    return ReadResult<std::int64_t>::success(std::bit_cast<std::int64_t>(result.value()));
}

ReadResult<float> BinaryReader::read_f32()
{
    auto result = read_u32();
    if (!result.has_value())
    {
        return ReadResult<float>::failure(result.error());
    }
    return ReadResult<float>::success(std::bit_cast<float>(result.value()));
}

ReadResult<double> BinaryReader::read_f64()
{
    auto result = read_u64();
    if (!result.has_value())
    {
        return ReadResult<double>::failure(result.error());
    }
    return ReadResult<double>::success(std::bit_cast<double>(result.value()));
}

ReadResult<std::span<const std::byte>> BinaryReader::read_bytes(const std::size_t count)
{
    if (!offset_range_valid_)
    {
        return ReadResult<std::span<const std::byte>>::failure(
            make_error(ReadErrorCode::offset_overflow, count, remaining()));
    }
    if (count > remaining())
    {
        return ReadResult<std::span<const std::byte>>::failure(
            make_error(ReadErrorCode::out_of_bounds, count, remaining()));
    }

    const auto result = bytes_.subspan(position_, count);
    position_ += count;
    return ReadResult<std::span<const std::byte>>::success(result);
}

ReadResult<std::monostate> BinaryReader::skip(const std::size_t count)
{
    auto result = read_bytes(count);
    if (!result.has_value())
    {
        return ReadResult<std::monostate>::failure(result.error());
    }
    return ReadResult<std::monostate>::success(std::monostate{});
}

ReadResult<std::monostate> BinaryReader::seek(const std::size_t position)
{
    if (!offset_range_valid_)
    {
        return ReadResult<std::monostate>::failure(
            make_error(ReadErrorCode::offset_overflow, position, size()));
    }
    if (position > size())
    {
        return ReadResult<std::monostate>::failure(
            make_error(ReadErrorCode::invalid_seek, position, size()));
    }
    position_ = position;
    return ReadResult<std::monostate>::success(std::monostate{});
}

ReadResult<std::uint64_t> BinaryReader::read_unsigned(const std::size_t byte_count)
{
    auto bytes = read_bytes(byte_count);
    if (!bytes.has_value())
    {
        return ReadResult<std::uint64_t>::failure(bytes.error());
    }

    std::uint64_t value = 0;
    for (std::size_t index = 0; index < byte_count; ++index)
    {
        const auto byte =
            static_cast<std::uint64_t>(std::to_integer<std::uint8_t>(bytes.value()[index]));
        if (byte_order_ == ByteOrder::little_endian)
        {
            const auto shift = static_cast<unsigned int>(index * 8U);
            value |= byte << shift;
        }
        else
        {
            value = (value << 8U) | byte;
        }
    }
    return ReadResult<std::uint64_t>::success(value);
}

ReadError BinaryReader::make_error(const ReadErrorCode code, const std::size_t requested,
                                   const std::size_t available) const
{
    return ReadError{
        .code = code,
        .absolute_offset = absolute_position(),
        .requested_bytes = as_u64(requested),
        .available_bytes = as_u64(available),
        .context = context_,
    };
}

} // namespace tmxy::format
