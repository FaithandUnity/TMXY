add_executable(tmxy_foundation_build_info_test build_info_test.cpp)

target_link_libraries(
    tmxy_foundation_build_info_test
    PRIVATE
        tmxy::foundation
        tmxy::project_options
        tmxy::project_warnings
)

add_test(NAME foundation.build_info COMMAND tmxy_foundation_build_info_test)

add_executable(tmxy_foundation_redaction_test redaction_test.cpp)

target_link_libraries(
    tmxy_foundation_redaction_test
    PRIVATE
        tmxy::foundation
        tmxy::project_options
        tmxy::project_warnings
)

add_test(NAME foundation.redaction COMMAND tmxy_foundation_redaction_test)
