add_executable(tmxy_asset_inventory apps/asset_inventory_main.cpp)
target_link_libraries(
    tmxy_asset_inventory
    PRIVATE
        tmxy::package
        tmxy::texture
        tmxy::static_mesh
        tmxy::skeletal_mesh
        tmxy::animation
        tmxy::terrain
)
tmxy_apply_tool_defaults(tmxy_asset_inventory)
