#pragma once

#include "tmxy/terrain/terrain_error.hpp"

#include <cassert>
#include <type_traits>
#include <utility>
#include <variant>

namespace tmxy::terrain
{

template <typename T> class [[nodiscard]] TerrainResult final
{
  public:
    [[nodiscard]] static TerrainResult success(T value)
    {
        return TerrainResult(std::move(value));
    }

    [[nodiscard]] static TerrainResult failure(TerrainError error)
    {
        return TerrainResult(std::move(error));
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

    [[nodiscard]] const TerrainError& error() const& noexcept
    {
        const auto* error = std::get_if<TerrainError>(&storage_);
        assert(error != nullptr);
        return *error;
    }

  private:
    explicit TerrainResult(T value) : storage_(std::move(value)) {}
    explicit TerrainResult(TerrainError error) : storage_(std::move(error)) {}

    std::variant<T, TerrainError> storage_;
};

} // namespace tmxy::terrain
