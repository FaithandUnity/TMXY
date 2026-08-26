add_library(tmxy_transform)
add_library(tmxy::transform ALIAS tmxy_transform)

target_sources(
    tmxy_transform
    PRIVATE
        src/legacy_to_ue_transform.cpp
        src/transform_error.cpp
)
target_include_directories(
    tmxy_transform
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)
tmxy_apply_tool_defaults(tmxy_transform)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
