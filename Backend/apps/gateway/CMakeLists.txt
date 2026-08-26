add_executable(tmxy_gateway src/main.cpp)
set_target_properties(tmxy_gateway PROPERTIES OUTPUT_NAME "tmxy-gateway")

target_link_libraries(
    tmxy_gateway
    PRIVATE
        tmxy::foundation
        tmxy::project_options
        tmxy::project_warnings
)
