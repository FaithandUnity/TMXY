add_library(tmxy_static_mesh)
add_library(tmxy::static_mesh ALIAS tmxy_static_mesh)

target_sources(
    tmxy_static_mesh
    PRIVATE
        src/package_static_mesh_reader.cpp
        src/sm_reader.cpp
        src/static_mesh_error.cpp
        src/static_mesh_export.cpp
        src/static_mesh_gltf.cpp
)
target_include_directories(
    tmxy_static_mesh
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)
target_link_libraries(
    tmxy_static_mesh
    PUBLIC
        tmxy::format_core
        tmxy::package
        tmxy::transform
)
tmxy_apply_tool_defaults(tmxy_static_mesh)

add_executable(tmxy_sm_export apps/sm_export_main.cpp)
target_link_libraries(tmxy_sm_export PRIVATE tmxy::static_mesh)
tmxy_apply_tool_defaults(tmxy_sm_export)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
