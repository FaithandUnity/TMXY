add_library(tmxy_terrain)
add_library(tmxy::terrain ALIAS tmxy_terrain)

target_sources(
    tmxy_terrain
    PRIVATE
        src/ter_reader.cpp
        src/terrain_error.cpp
        src/terrain_export.cpp
)
target_include_directories(
    tmxy_terrain
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)
target_link_libraries(tmxy_terrain PUBLIC tmxy::format_core)
tmxy_apply_tool_defaults(tmxy_terrain)

add_executable(tmxy_ter_export apps/ter_export_main.cpp)
target_link_libraries(tmxy_ter_export PRIVATE tmxy::terrain)
tmxy_apply_tool_defaults(tmxy_ter_export)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
