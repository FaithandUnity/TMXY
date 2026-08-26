add_library(tmxy_texture)
add_library(tmxy::texture ALIAS tmxy_texture)

target_sources(
    tmxy_texture
    PRIVATE
        src/block_compression.cpp
        src/dds_writer.cpp
        src/legacy_texture_descriptor_reader.cpp
        src/package_texture_reader.cpp
        src/png_writer.cpp
        src/qtx_reader.cpp
        src/texture_decode.cpp
        src/texture_error.cpp
        src/texture_export.cpp
        src/tga_writer.cpp
)
target_include_directories(
    tmxy_texture
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)
target_link_libraries(tmxy_texture PUBLIC tmxy::format_core tmxy::package)
tmxy_apply_tool_defaults(tmxy_texture)

add_executable(tmxy_qtx_export apps/qtx_export_main.cpp)
target_link_libraries(tmxy_qtx_export PRIVATE tmxy::texture)
tmxy_apply_tool_defaults(tmxy_qtx_export)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
