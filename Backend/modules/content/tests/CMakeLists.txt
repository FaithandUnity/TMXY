add_executable(tmxy_content_generated_types_test generated_types_test.cpp)

target_link_libraries(
    tmxy_content_generated_types_test
    PRIVATE
        tmxy::content
        tmxy::project_options
        tmxy::project_warnings
)

add_test(NAME content.generated_types COMMAND tmxy_content_generated_types_test)
