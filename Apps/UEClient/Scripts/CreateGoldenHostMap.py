"""Create only the fixed P1-20 golden automation host map."""

import unreal


GOLDEN_ROOT = "/Game/TMXY/Golden"
GOLDEN_MAP = "/Game/TMXY/Golden/Maps/TMXYGoldenTestMap"


def create_golden_host_map() -> None:
    level_editor = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    editor_assets = unreal.get_editor_subsystem(unreal.EditorAssetSubsystem)
    if level_editor is None:
        raise RuntimeError("LevelEditorSubsystem is unavailable")
    if editor_assets is None:
        raise RuntimeError("EditorAssetSubsystem is unavailable")

    if editor_assets.does_asset_exist(GOLDEN_MAP):
        if not level_editor.load_level(GOLDEN_MAP):
            raise RuntimeError(f"Could not load existing golden map: {GOLDEN_MAP}")
    elif not level_editor.new_level(GOLDEN_MAP, False):
        raise RuntimeError(f"Could not create golden map: {GOLDEN_MAP}")

    if not level_editor.save_current_level():
        raise RuntimeError(f"Could not save golden map: {GOLDEN_MAP}")

    unreal.log(f"TMXY_GOLDEN_HOST_MAP_READY root={GOLDEN_ROOT} map={GOLDEN_MAP}")


create_golden_host_map()
