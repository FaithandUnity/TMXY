add_library(tmxy_package)
add_library(tmxy::package ALIAS tmxy_package)

target_sources(
    tmxy_package
    PRIVATE
        src/package_directory_codec.cpp
        src/package_normalized_tree.cpp
        src/package_v1.cpp
        src/package_v1_reader.cpp
        src/package_v2.cpp
        src/package_v2_reader.cpp
        src/package_v3.cpp
        src/package_v3_reader.cpp
)
target_include_directories(
    tmxy_package
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)
target_link_libraries(tmxy_package PUBLIC tmxy::format_core)
tmxy_apply_tool_defaults(tmxy_package)

add_executable(tmxy_package_tree_export apps/package_tree_export_main.cpp)
target_link_libraries(tmxy_package_tree_export PRIVATE tmxy::package)
tmxy_apply_tool_defaults(tmxy_package_tree_export)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
