add_library(tmxy_content INTERFACE)
add_library(tmxy::content ALIAS tmxy_content)

get_filename_component(TMXY_REBUILD_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)

target_include_directories(
    tmxy_content
    INTERFACE
        "${TMXY_REBUILD_ROOT}/Contracts/generated/cpp"
)

target_link_libraries(tmxy_content INTERFACE tmxy::project_options)
