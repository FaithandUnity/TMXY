#pragma once

#include "tmxy/format/read_result.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>

namespace tmxy::format
{

enum class ByteOrder : std::uint8_t
{
    little_endian = 1,
    big_endian = 2,
};

class BinaryReader final
{
  public:
    explicit BinaryReader(std::span<const std::byte> bytes,
                          ByteOrder byte_order = ByteOrder::little_endian,
                          std::uint64_t base_offset = 0, std::string context = {});

    [[nodiscard]] std::size_t size() const noexcept;
    [[nodiscard]] std::size_t position() const noexcept;
    [[nodiscard]] std::size_t remaining() const noexcept;
    [[nodiscard]] std::uint64_t absolute_position() const noexcept;
    [[nodiscard]] std::string_view context() const noexcept;
    [[nodiscard]] bool offset_range_valid() const noexcept;

    [[nodiscard]] ReadResult<std::uint8_t> read_u8();
    [[nodiscard]] ReadResult<std::uint16_t> read_u16();
    [[nodiscard]] ReadResult<std::uint32_t> read_u32();
    [[nodiscard]] ReadResult<std::uint64_t> read_u64();
    [[nodiscard]] ReadResult<std::int8_t> read_i8();
    [[nodiscard]] ReadResult<std::int16_t> read_i16();
    [[nodiscard]] ReadResult<std::int32_t> read_i32();
    [[nodiscard]] ReadResult<std::int64_t> read_i64();
    [[nodiscard]] ReadResult<float> read_f32();
    [[nodiscard]] ReadResult<double> read_f64();
    [[nodiscard]] ReadResult<std::span<const std::byte>> read_bytes(std::size_t count);
    [[nodiscard]] ReadResult<std::monostate> skip(std::size_t count);
    [[nodiscard]] ReadResult<std::monostate> seek(std::size_t position);

  private:
    [[nodiscard]] ReadResult<std::uint64_t> read_unsigned(std::size_t byte_count);
    [[nodiscard]] ReadError make_error(ReadErrorCode code, std::size_t requested,
                                       std::size_t available) const;

    std::span<const std::byte> bytes_;
    ByteOrder byte_order_;
    std::uint64_t base_offset_;
    std::size_t position_{0};
    std::string context_;
    bool offset_range_valid_{true};
};

} // namespace tmxy::format
