add_library(tmxy_skeletal_mesh)
add_library(tmxy::skeletal_mesh ALIAS tmxy_skeletal_mesh)

target_sources(
    tmxy_skeletal_mesh
    PRIVATE
        src/package_skeletal_mesh_reader.cpp
        src/skem_reader.cpp
        src/skeletal_mesh_binding.cpp
        src/skeletal_mesh_error.cpp
        src/skeletal_mesh_export.cpp
        src/skeletal_mesh_gltf.cpp
        src/skeletal_mesh_gltf_json.cpp
)
target_include_directories(
    tmxy_skeletal_mesh
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)
target_link_libraries(
    tmxy_skeletal_mesh
    PUBLIC
        tmxy::format_core
        tmxy::package
        tmxy::transform
)
tmxy_apply_tool_defaults(tmxy_skeletal_mesh)

add_executable(tmxy_skem_export apps/skem_export_main.cpp)
target_link_libraries(tmxy_skem_export PRIVATE tmxy::skeletal_mesh)
tmxy_apply_tool_defaults(tmxy_skem_export)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
