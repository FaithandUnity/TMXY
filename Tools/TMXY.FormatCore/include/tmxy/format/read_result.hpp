#pragma once

#include "tmxy/format/read_error.hpp"

#include <cassert>
#include <type_traits>
#include <utility>
#include <variant>

namespace tmxy::format
{

template <typename T> class [[nodiscard]] ReadResult final
{
  public:
    [[nodiscard]] static ReadResult success(T value)
    {
        return ReadResult(std::move(value));
    }

    [[nodiscard]] static ReadResult failure(ReadError error)
    {
        return ReadResult(std::move(error));
    }

    [[nodiscard]] bool has_value() const noexcept
    {
        return std::holds_alternative<T>(storage_);
    }

    [[nodiscard]] const T& value() const& noexcept
    {
        const auto* result = std::get_if<T>(&storage_);
        assert(result != nullptr);
        return *result;
    }

    [[nodiscard]] T take_value() && noexcept(std::is_nothrow_move_constructible_v<T>)
    {
        auto* result = std::get_if<T>(&storage_);
        assert(result != nullptr);
        return std::move(*result);
    }

    [[nodiscard]] const ReadError& error() const& noexcept
    {
        const auto* result = std::get_if<ReadError>(&storage_);
        assert(result != nullptr);
        return *result;
    }

  private:
    explicit ReadResult(T value) : storage_(std::move(value)) {}
    explicit ReadResult(ReadError error) : storage_(std::move(error)) {}

    std::variant<T, ReadError> storage_;
};

} // namespace tmxy::format
