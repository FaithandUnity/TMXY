add_library(tmxy_animation)
add_library(tmxy::animation ALIAS tmxy_animation)

target_sources(
    tmxy_animation
    PRIVATE
        src/anim_reader.cpp
        src/animation_error.cpp
        src/animation_export.cpp
        src/animation_gltf.cpp
        src/package_animation_reader.cpp
        src/package_object_index.cpp
)
target_include_directories(
    tmxy_animation
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)
target_link_libraries(
    tmxy_animation
    PUBLIC
        tmxy::format_core
        tmxy::package
        tmxy::skeletal_mesh
        tmxy::transform
)
tmxy_apply_tool_defaults(tmxy_animation)

add_executable(tmxy_anim_export apps/anim_export_main.cpp)
target_link_libraries(tmxy_anim_export PRIVATE tmxy::animation)
tmxy_apply_tool_defaults(tmxy_anim_export)

add_executable(tmxy_anim_gltf_export apps/anim_gltf_export_main.cpp)
target_link_libraries(tmxy_anim_gltf_export PRIVATE tmxy::animation)
tmxy_apply_tool_defaults(tmxy_anim_gltf_export)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
