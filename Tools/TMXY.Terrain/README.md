# TMXY.Terrain

`TMXY.Terrain` is the bounded, offline reader and deterministic exporter for legacy `.ter`
terrain tiles. It has no dependency on the legacy runtime or Unreal Engine.

The library preserves the 36-byte source vertex record, derives the square grid resolution,
validates the water and active-layer tail, and exposes height, layer-alpha, and four-edge data.
The CLI writes:

- `<stem>.json`: tile identity, grid dimensions, height statistics, water, and active layers;
- `<stem>.height.f32le`: row-major source height samples as little-endian float32;
- `<stem>.layers.rgba8`: four source layer-alpha bytes per row-major vertex;
- `<stem>.edges.csv`: complete top/right/bottom/left vertex records in natural axis order.

Usage:

```text
tmxy_ter_export <ter-file> <output-stem>
```

The exporter deliberately does not infer world scale. The legacy level package supplies zone
size, while `.ter` supplies the 64×64 samples; that binding belongs to later level reconstruction.
