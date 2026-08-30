cmake_minimum_required(VERSION 3.25)

project(
    TMXYBackend
    VERSION 0.1.0
    DESCRIPTION "TMXY Linux backend"
    LANGUAGES CXX
)

include(CTest)

option(TMXY_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" ON)

set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(cmake/TMXYProjectOptions.cmake)

add_subdirectory(modules/foundation)
add_subdirectory(modules/content)
add_subdirectory(apps/gateway)

if(BUILD_TESTING)
    add_subdirectory(modules/foundation/tests)
    add_subdirectory(modules/content/tests)
endif()
