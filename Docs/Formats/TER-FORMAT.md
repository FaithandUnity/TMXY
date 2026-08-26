# TER terrain tile format

Status: P1-17 evidence-backed reader contract.

## Evidence boundary

The format was recovered from read-only legacy sources and verified against installed-client
files. `QTerrain::loadTerrainData` reads a `QArray<TerrainVertex>`, a one-byte boolean, water
height, and an integer layer array, followed by an optional `QColor`. `saveTerrainData` asserts
`64*64` vertices. `TerrainVertex` is serialized as its complete 36-byte in-memory record.

## Little-endian layout

| Field | Encoding | Validation |
|---|---|---|
| vertex count | signed int32 | positive bounded perfect square; installed files use 4096 |
| vertices | count × 36 bytes | finite height, normal, and color components |
| water enabled | uint8 | exactly 0 or 1 |
| water height | float32 | finite |
| active layer count | signed int32 | 0–4 |
| active layer indices | count × signed int32 | unique non-negative package layer references, order preserved |
| water color | optional 4 × float32 | tail is either absent or exactly 16 finite bytes |

Each vertex is `height f32`, `normal xyz f32`, `color rgba f32`, then four unsigned layer-alpha
bytes. The four alpha bytes address local slots in the ordered active-layer list; the stored layer
references are not restricted to 0–3 (for example, a real `world` tile uses 0, 3, 29, 15).
Vertices are row-major and X changes fastest. The installed corpus contains 8,876 files;
all use 4,096 vertices, so each edge has 64 vertices and each axis has 63 terrain cells. File
sizes are 147,485–147,501 bytes according to active layer count and optional water color.

## Edge contract

Edges are exported as top (`y=0`), right (`x=63`), bottom (`y=63`), and left (`x=0`). Samples
within each edge retain increasing source X or Y. This makes right-to-left and bottom-to-top
adjacency comparisons direct, without reversing either side.

The installed non-flat `world_001_001` neighborhood contains small pre-existing height
differences on shared edges. The reader preserves and reports those values; it does not silently
weld or mutate evidence. Any repair policy belongs to the later UE terrain import stage.

## Scale boundary

`.ter` does not contain physical zone size. Legacy code applies `level.zoneSize / tileNum` as a
uniform transform. P1-17 therefore exports exact source height units and does not guess meters or
centimeters without the matching level metadata.
