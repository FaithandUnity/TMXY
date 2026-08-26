#pragma once

#include "tmxy/texture/texture_error.hpp"

#include <cassert>
#include <utility>
#include <variant>

namespace tmxy::texture
{

template <typename Value> class [[nodiscard]] TextureResult final
{
  public:
    [[nodiscard]] static TextureResult success(Value value)
    {
        return TextureResult(std::move(value));
    }

    [[nodiscard]] static TextureResult failure(TextureError error)
    {
        return TextureResult(std::move(error));
    }

    [[nodiscard]] bool has_value() const noexcept
    {
        return std::holds_alternative<Value>(storage_);
    }

    [[nodiscard]] const Value& value() const& noexcept
    {
        const auto* value = std::get_if<Value>(&storage_);
        assert(value != nullptr);
        return *value;
    }
    [[nodiscard]] Value&& value() && noexcept
    {
        auto* value = std::get_if<Value>(&storage_);
        assert(value != nullptr);
        return std::move(*value);
    }
    [[nodiscard]] const TextureError& error() const& noexcept
    {
        const auto* error = std::get_if<TextureError>(&storage_);
        assert(error != nullptr);
        return *error;
    }

  private:
    explicit TextureResult(Value value) : storage_(std::move(value)) {}
    explicit TextureResult(TextureError error) : storage_(std::move(error)) {}

    std::variant<Value, TextureError> storage_;
};

} // namespace tmxy::texture
