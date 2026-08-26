#pragma once

#include "tmxy/skeletal_mesh/skeletal_mesh_error.hpp"

#include <cassert>
#include <type_traits>
#include <utility>
#include <variant>

namespace tmxy::skeletal_mesh
{

template <typename T> class [[nodiscard]] SkeletalMeshResult final
{
  public:
    [[nodiscard]] static SkeletalMeshResult success(T value)
    {
        return SkeletalMeshResult(std::move(value));
    }

    [[nodiscard]] static SkeletalMeshResult failure(SkeletalMeshError error)
    {
        return SkeletalMeshResult(std::move(error));
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

    [[nodiscard]] const SkeletalMeshError& error() const& noexcept
    {
        const auto* error = std::get_if<SkeletalMeshError>(&storage_);
        assert(error != nullptr);
        return *error;
    }

  private:
    explicit SkeletalMeshResult(T value) : storage_(std::move(value)) {}
    explicit SkeletalMeshResult(SkeletalMeshError error) : storage_(std::move(error)) {}

    std::variant<T, SkeletalMeshError> storage_;
};

} // namespace tmxy::skeletal_mesh
