#pragma once

#include "tmxy/static_mesh/static_mesh_error.hpp"

#include <cassert>
#include <type_traits>
#include <utility>
#include <variant>

namespace tmxy::static_mesh
{

template <typename T> class [[nodiscard]] StaticMeshResult final
{
  public:
    [[nodiscard]] static StaticMeshResult success(T value)
    {
        return StaticMeshResult(std::move(value));
    }

    [[nodiscard]] static StaticMeshResult failure(StaticMeshError error)
    {
        return StaticMeshResult(std::move(error));
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

    [[nodiscard]] const StaticMeshError& error() const& noexcept
    {
        const auto* error = std::get_if<StaticMeshError>(&storage_);
        assert(error != nullptr);
        return *error;
    }

  private:
    explicit StaticMeshResult(T value) : storage_(std::move(value)) {}
    explicit StaticMeshResult(StaticMeshError error) : storage_(std::move(error)) {}

    std::variant<T, StaticMeshError> storage_;
};

} // namespace tmxy::static_mesh
