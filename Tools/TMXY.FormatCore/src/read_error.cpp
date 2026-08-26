#include "tmxy/format/read_error.hpp"

namespace tmxy::format
{

std::string_view to_string(const ReadErrorCode code) noexcept
{
    switch (code)
    {
    case ReadErrorCode::out_of_bounds:
        return "out_of_bounds";
    case ReadErrorCode::invalid_seek:
        return "invalid_seek";
    case ReadErrorCode::offset_overflow:
        return "offset_overflow";
    }
    return "unknown_read_error";
}

} // namespace tmxy::format
