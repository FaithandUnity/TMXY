cmake_minimum_required(VERSION 3.25)

project(
    TMXYTools
    VERSION 0.1.0
    DESCRIPTION "TMXY offline reconstruction tools"
    LANGUAGES CXX
)

include(CTest)

option(TMXY_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" ON)
option(TMXY_BUILD_PACKAGE "Build the Package reconstruction module" ON)
option(TMXY_BUILD_TABLE "Build the legacy Table reconstruction module" ON)
option(TMXY_BUILD_TRANSFORM "Build the legacy-to-UE transform module" ON)
option(TMXY_BUILD_TEXTURE "Build the legacy qtx texture reconstruction module" ON)
option(TMXY_BUILD_STATIC_MESH "Build the legacy sm static-mesh reconstruction module" ON)
option(TMXY_BUILD_SKELETAL_MESH "Build the legacy skem skeletal-mesh reconstruction module" ON)
option(TMXY_BUILD_ANIMATION "Build the legacy anim skeletal-animation reconstruction module" ON)
option(TMXY_BUILD_TERRAIN "Build the legacy ter terrain reconstruction module" ON)
option(TMXY_BUILD_ASSET_INVENTORY "Build the full legacy asset inventory scanner" OFF)
option(TMXY_BUILD_G2_ASSET_DESCRIPTOR_DIAGNOSTICS
       "Build the P2-20A.4 full-semantic descriptor diagnostic probe" OFF)

set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(cmake/TMXYToolOptions.cmake)

add_subdirectory(TMXY.FormatCore)
if(TMXY_BUILD_PACKAGE)
    add_subdirectory(TMXY.Package)
endif()
if(TMXY_BUILD_TABLE)
    add_subdirectory(TMXY.Table)
endif()
if(TMXY_BUILD_TRANSFORM)
    add_subdirectory(TMXY.Transform)
endif()
if(TMXY_BUILD_TEXTURE)
    if(NOT TMXY_BUILD_PACKAGE)
        message(FATAL_ERROR "TMXY.Texture requires TMXY.Package")
    endif()
    add_subdirectory(TMXY.Texture)
endif()
if(TMXY_BUILD_STATIC_MESH)
    if(NOT TMXY_BUILD_PACKAGE OR NOT TMXY_BUILD_TRANSFORM)
        message(FATAL_ERROR "TMXY.StaticMesh requires TMXY.Package and TMXY.Transform")
    endif()
    add_subdirectory(TMXY.StaticMesh)
endif()
if(TMXY_BUILD_SKELETAL_MESH)
    if(NOT TMXY_BUILD_PACKAGE OR NOT TMXY_BUILD_TRANSFORM)
        message(FATAL_ERROR "TMXY.SkeletalMesh requires TMXY.Package and TMXY.Transform")
    endif()
    add_subdirectory(TMXY.SkeletalMesh)
endif()
if(TMXY_BUILD_ANIMATION)
    if(NOT TMXY_BUILD_PACKAGE OR NOT TMXY_BUILD_TRANSFORM OR NOT TMXY_BUILD_SKELETAL_MESH)
        message(FATAL_ERROR "TMXY.Animation requires TMXY.Package, TMXY.Transform, and TMXY.SkeletalMesh")
    endif()
    add_subdirectory(TMXY.Animation)
endif()
if(TMXY_BUILD_TERRAIN)
    add_subdirectory(TMXY.Terrain)
endif()
if(TMXY_BUILD_ASSET_INVENTORY)
    if(NOT TMXY_BUILD_PACKAGE OR NOT TMXY_BUILD_TRANSFORM OR NOT TMXY_BUILD_TEXTURE OR
       NOT TMXY_BUILD_STATIC_MESH OR NOT TMXY_BUILD_SKELETAL_MESH OR NOT TMXY_BUILD_ANIMATION OR
       NOT TMXY_BUILD_TERRAIN)
        message(FATAL_ERROR "TMXY.AssetInventory requires all Package and asset format modules")
    endif()
    add_subdirectory(TMXY.AssetInventory)
endif()
if(TMXY_BUILD_G2_ASSET_DESCRIPTOR_DIAGNOSTICS)
    if(NOT TMXY_BUILD_PACKAGE OR NOT TMXY_BUILD_TRANSFORM OR NOT TMXY_BUILD_TEXTURE OR
       NOT TMXY_BUILD_STATIC_MESH OR NOT TMXY_BUILD_SKELETAL_MESH OR NOT TMXY_BUILD_ANIMATION)
        message(FATAL_ERROR
                "TMXY.G2AssetDescriptorDiagnostics requires Package, Transform, Texture, StaticMesh, SkeletalMesh, and Animation")
    endif()
    add_subdirectory(TMXY.G2AssetDescriptorDiagnostics)
endif()
