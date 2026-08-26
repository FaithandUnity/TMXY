add_library(tmxy_table)
add_library(tmxy::table ALIAS tmxy_table)

target_sources(
    tmxy_table
    PRIVATE
        src/aes128_decryptor.cpp
        src/legacy_table.cpp
        src/legacy_table_reader.cpp
)
target_include_directories(
    tmxy_table
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)
tmxy_apply_tool_defaults(tmxy_table)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
