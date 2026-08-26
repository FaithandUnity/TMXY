add_library(tmxy_format_core)
add_library(tmxy::format_core ALIAS tmxy_format_core)

target_sources(
    tmxy_format_core
    PRIVATE
        src/binary_reader.cpp
        src/read_error.cpp
)
target_include_directories(
    tmxy_format_core
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)
tmxy_apply_tool_defaults(tmxy_format_core)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
