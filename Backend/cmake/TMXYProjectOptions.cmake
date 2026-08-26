add_library(tmxy_project_options INTERFACE)
add_library(tmxy::project_options ALIAS tmxy_project_options)
target_compile_features(tmxy_project_options INTERFACE cxx_std_20)

add_library(tmxy_project_warnings INTERFACE)
add_library(tmxy::project_warnings ALIAS tmxy_project_warnings)

if(MSVC)
    target_compile_options(tmxy_project_warnings INTERFACE /permissive- /W4)
    if(TMXY_WARNINGS_AS_ERRORS)
        target_compile_options(tmxy_project_warnings INTERFACE /WX)
    endif()
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(
        tmxy_project_warnings
        INTERFACE
            -Wall
            -Wconversion
            -Wextra
            -Wpedantic
            -Wshadow
            -Wsign-conversion
    )
    if(TMXY_WARNINGS_AS_ERRORS)
        target_compile_options(tmxy_project_warnings INTERFACE -Werror)
    endif()
else()
    message(FATAL_ERROR "Unsupported C++ compiler: ${CMAKE_CXX_COMPILER_ID}")
endif()
