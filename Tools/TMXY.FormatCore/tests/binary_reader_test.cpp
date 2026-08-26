#include "tmxy/format/binary_reader.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
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
            ++failure_count_;
            std::cerr << "FAILED: " << message << '\n';
        }
    }

    [[nodiscard]] int failure_count() const noexcept
    {
        return failure_count_;
    }

  private:
    int failure_count_{0};
};

void test_little_endian_reads(TestContext& test)
{
    const std::array bytes{
        std::byte{0x01}, std::byte{0x02}, std::byte{0x03}, std::byte{0x04},
        std::byte{0x05}, std::byte{0x06}, std::byte{0x07}, std::byte{0x08},
    };
    tmxy::format::BinaryReader reader(bytes, tmxy::format::ByteOrder::little_endian, 32);
    const auto first = reader.read_u16();
    const auto second = reader.read_u32();

    test.expect(first.has_value() && first.value() == 0x0201U, "little-endian u16");
    test.expect(second.has_value() && second.value() == 0x06050403U, "little-endian u32");
    test.expect(reader.position() == 6U, "sequential cursor position");
    test.expect(reader.absolute_position() == 38U, "absolute cursor position");
    test.expect(reader.remaining() == 2U, "remaining bytes");
}

void test_big_endian_reads(TestContext& test)
{
    const std::array bytes{
        std::byte{0x01}, std::byte{0x02}, std::byte{0x03}, std::byte{0x04},
        std::byte{0x05}, std::byte{0x06}, std::byte{0x07}, std::byte{0x08},
    };
    tmxy::format::BinaryReader reader(bytes, tmxy::format::ByteOrder::big_endian);
    const auto first = reader.read_u16();
    const auto second = reader.read_u32();

    test.expect(first.has_value() && first.value() == 0x0102U, "big-endian u16");
    test.expect(second.has_value() && second.value() == 0x03040506U, "big-endian u32");
}

void test_signed_and_float_reads(TestContext& test)
{
    const std::array bytes{
        std::byte{0xFE}, std::byte{0xFF}, std::byte{0xFE}, std::byte{0x00},
        std::byte{0x00}, std::byte{0x80}, std::byte{0x3F},
    };
    tmxy::format::BinaryReader reader(bytes);
    const auto signed_byte = reader.read_i8();
    const auto signed_word = reader.read_i16();
    const auto value = reader.read_f32();

    test.expect(signed_byte.has_value() && signed_byte.value() == -2, "signed i8");
    test.expect(signed_word.has_value() && signed_word.value() == -257, "signed i16");
    test.expect(value.has_value() && value.value() == 1.0F, "IEEE-754 f32");
}

void test_out_of_bounds_is_stable(TestContext& test)
{
    const std::array bytes{std::byte{0xAA}, std::byte{0xBB}};
    tmxy::format::BinaryReader reader(bytes, tmxy::format::ByteOrder::little_endian, 100,
                                      "package.header.magic");
    const auto result = reader.read_u32();

    test.expect(!result.has_value(), "truncated read fails");
    test.expect(result.error().code == tmxy::format::ReadErrorCode::out_of_bounds,
                "truncated read code");
    test.expect(result.error().absolute_offset == 100U, "truncated absolute offset");
    test.expect(result.error().requested_bytes == 4U, "truncated requested bytes");
    test.expect(result.error().available_bytes == 2U, "truncated available bytes");
    test.expect(result.error().context == "package.header.magic", "truncated context");
    test.expect(reader.position() == 0U, "failed read does not move cursor");
}

void test_seek_and_exact_boundary(TestContext& test)
{
    const std::array bytes{std::byte{0x10}, std::byte{0x20}, std::byte{0x30}};
    tmxy::format::BinaryReader reader(bytes);
    const auto seek = reader.seek(1);
    const auto value = reader.read_u16();
    const auto past_end = reader.read_u8();
    const auto invalid_seek = reader.seek(4);

    test.expect(seek.has_value(), "valid seek");
    test.expect(value.has_value() && value.value() == 0x3020U, "exact-boundary read");
    test.expect(!past_end.has_value(), "read after exact boundary fails");
    test.expect(!invalid_seek.has_value(), "invalid seek fails");
    test.expect(invalid_seek.error().code == tmxy::format::ReadErrorCode::invalid_seek,
                "invalid seek code");
    test.expect(reader.position() == 3U, "failed seek does not move cursor");
}

void test_byte_view_and_skip(TestContext& test)
{
    const std::array bytes{
        std::byte{0x11},
        std::byte{0x22},
        std::byte{0x33},
        std::byte{0x44},
    };
    tmxy::format::BinaryReader reader(bytes);
    const auto skipped = reader.skip(1);
    const auto view = reader.read_bytes(2);
    const auto empty = reader.read_bytes(0);

    test.expect(skipped.has_value(), "bounded skip");
    test.expect(view.has_value() && view.value().size() == 2U, "bounded byte view");
    test.expect(view.has_value() && view.value()[0] == std::byte{0x22}, "byte view content");
    test.expect(empty.has_value() && empty.value().empty(), "zero-length read");
    test.expect(reader.position() == 3U, "byte view cursor");
}

void test_offset_overflow(TestContext& test)
{
    const std::array bytes{std::byte{0x01}, std::byte{0x02}};
    tmxy::format::BinaryReader reader(bytes, tmxy::format::ByteOrder::little_endian,
                                      std::numeric_limits<std::uint64_t>::max());
    const auto result = reader.read_u8();

    test.expect(!reader.offset_range_valid(), "overflow range rejected at construction");
    test.expect(!result.has_value(), "overflow read fails");
    test.expect(result.error().code == tmxy::format::ReadErrorCode::offset_overflow,
                "overflow error code");
    test.expect(reader.position() == 0U, "overflow read does not move cursor");
}

void test_error_contract(TestContext& test)
{
    test.expect(tmxy::format::ReadError::kSchemaVersion == 1U, "error schema version");
    test.expect(tmxy::format::to_string(tmxy::format::ReadErrorCode::out_of_bounds) ==
                    "out_of_bounds",
                "stable error name");
}

} // namespace

int main()
{
    TestContext test;
    test_little_endian_reads(test);
    test_big_endian_reads(test);
    test_signed_and_float_reads(test);
    test_out_of_bounds_is_stable(test);
    test_seek_and_exact_boundary(test);
    test_byte_view_and_skip(test);
    test_offset_overflow(test);
    test_error_contract(test);
    return test.failure_count() == 0 ? 0 : 1;
}
