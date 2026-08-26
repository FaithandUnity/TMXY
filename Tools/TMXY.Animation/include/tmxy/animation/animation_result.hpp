#pragma once

#include "tmxy/animation/animation_error.hpp"

#include <cassert>
#include <type_traits>
#include <utility>
#include <variant>

namespace tmxy::animation
{

template <typename T> class [[nodiscard]] AnimationResult final
{
  public:
    [[nodiscard]] static AnimationResult success(T value)
    {
        return AnimationResult(std::move(value));
    }

    [[nodiscard]] static AnimationResult failure(AnimationError error)
    {
        return AnimationResult(std::move(error));
    }

    [[nodiscard]] bool has_value() const noexcept
    {
        return std::holds_alternative<T>(storage_);
    }

    [[nodiscard]] const T& value() const& noexcept
    {
        const auto* value = std::get_if<T>(&storage_);
        assert(value != nullptr);
        return *value;
    }

    [[nodiscard]] T take_value() && noexcept(std::is_nothrow_move_constructible_v<T>)
    {
        auto* value = std::get_if<T>(&storage_);
        assert(value != nullptr);
        return std::move(*value);
    }

    [[nodiscard]] const AnimationError& error() const& noexcept
    {
        const auto* error = std::get_if<AnimationError>(&storage_);
        assert(error != nullptr);
        return *error;
    }

  private:
    explicit AnimationResult(T value) : storage_(std::move(value)) {}
    explicit AnimationResult(AnimationError error) : storage_(std::move(error)) {}

    std::variant<T, AnimationError> storage_;
};

} // namespace tmxy::animation
