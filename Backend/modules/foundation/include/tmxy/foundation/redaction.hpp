#pragma once

#include <string>
#include <string_view>

namespace tmxy::foundation
{
[[nodiscard]] std::string redact_sensitive_text(std::string_view text);
} // namespace tmxy::foundation
