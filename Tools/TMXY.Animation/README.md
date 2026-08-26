# TMXY.Animation

`TMXY.Animation` reconstructs legacy skeletal-animation evidence without loading legacy runtime
code. It binds `QSkelAnim` metadata from a Package to the matching headerless `.anim` stream,
validates dense prefix bone tracks and keys, and emits deterministic JSON plus root-track CSV.

The module preserves legacy meters and quaternion components in parsed data. Its report also
provides Unreal-centimeter root translation deltas. A later Unreal importer owns engine asset
creation and final quaternion basis conversion.
