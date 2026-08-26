add_library(tmxy_foundation STATIC)
add_library(tmxy::foundation ALIAS tmxy_foundation)

target_sources(
    tmxy_foundation
    PRIVATE
        src/build_info.cpp
        src/redaction.cpp
    PUBLIC
        FILE_SET public_headers
        TYPE HEADERS
        BASE_DIRS include
        FILES
            include/tmxy/foundation/build_info.hpp
            include/tmxy/foundation/redaction.hpp
)

target_link_libraries(
    tmxy_foundation
    PUBLIC tmxy::project_options
    PRIVATE tmxy::project_warnings
)
