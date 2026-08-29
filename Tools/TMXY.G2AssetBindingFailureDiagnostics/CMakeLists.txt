cmake_minimum_required(VERSION 3.25)

project(TMXYG2AssetBindingFailureDiagnostics LANGUAGES CXX)

set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(TMXY_WARNINGS_AS_ERRORS ON CACHE BOOL "" FORCE)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/TMXYToolOptions.cmake)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../TMXY.FormatCore ${CMAKE_BINARY_DIR}/format-core EXCLUDE_FROM_ALL)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../TMXY.Package ${CMAKE_BINARY_DIR}/package EXCLUDE_FROM_ALL)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../TMXY.Transform ${CMAKE_BINARY_DIR}/transform EXCLUDE_FROM_ALL)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../TMXY.Texture ${CMAKE_BINARY_DIR}/texture EXCLUDE_FROM_ALL)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../TMXY.StaticMesh ${CMAKE_BINARY_DIR}/static-mesh EXCLUDE_FROM_ALL)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../TMXY.SkeletalMesh ${CMAKE_BINARY_DIR}/skeletal-mesh EXCLUDE_FROM_ALL)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../TMXY.Animation ${CMAKE_BINARY_DIR}/animation EXCLUDE_FROM_ALL)

add_executable(
    tmxy_g2_asset_binding_failure_probe
    apps/failure_probe_main.cpp
    apps/probe_support.cpp
    ../TMXY.G2AssetDescriptorDiagnostics/sha256.cpp
)
target_include_directories(
    tmxy_g2_asset_binding_failure_probe
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/apps
        ${CMAKE_CURRENT_SOURCE_DIR}/../TMXY.G2AssetDescriptorDiagnostics
)
target_link_libraries(
    tmxy_g2_asset_binding_failure_probe
    PRIVATE
        tmxy::package
        tmxy::texture
        tmxy::static_mesh
        tmxy::skeletal_mesh
        tmxy::animation
)
tmxy_apply_tool_defaults(tmxy_g2_asset_binding_failure_probe)
