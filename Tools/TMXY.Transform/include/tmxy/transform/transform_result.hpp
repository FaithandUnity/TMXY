#pragma once

#include "tmxy/transform/transform_error.hpp"

#include <cassert>
#include <type_traits>
#include <utility>
#include <variant>

namespace tmxy::transform
{

template <typename T> class [[nodiscard]] TransformResult final
{
  public:
    [[nodiscard]] static TransformResult success(T value)
    {
        return TransformResult(std::move(value));
    }

    [[nodiscard]] static TransformResult failure(TransformError error)
    {
        return TransformResult(error);
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

    [[nodiscard]] const TransformError& error() const& noexcept
    {
        const auto* result = std::get_if<TransformError>(&storage_);
        assert(result != nullptr);
        return *result;
    }

  private:
    explicit TransformResult(T value) : storage_(std::move(value)) {}
    explicit TransformResult(TransformError error) : storage_(error) {}

    std::variant<T, TransformError> storage_;
};

} // namespace tmxy::transform
