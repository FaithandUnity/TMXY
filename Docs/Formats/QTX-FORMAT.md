# Legacy QTX texture contract

Status: P1-13 frozen evidence contract, schema version 1.

## 1. Scope and source boundary

`qtx` is not a self-describing image container. A legacy `QTexture` object in a
Package supplies the descriptor, while
`Resource/Texture/<package>/<object>.qtx` contains only the concatenated mip
payload. The reconstruction pipeline therefore always requires both inputs.
Its default binder never infers width, height, format, or mip count from payload
length alone.

The Package object body uses `QObject::serialize` records:

| Field | Encoding |
|---|---|
| item count | little-endian `uint16` |
| property name | little-endian `uint16` byte count followed by name bytes |
| property payload size | little-endian `uint16` |
| property payload | property-specific bytes |

`QTextureBase` registers `format`, `uClamp`, `vClamp`, `uSize`, `vSize`, and
`mipLevel`. Each is a little-endian 32-bit integer when present. Serialization
omits values equal to the class default, so absent properties use zero. In
particular, absent `format` means `TF_RGBA8`; the old renderer promotes a stored
`mipLevel` of zero to one before allocating the D3D texture.

Unknown property records are preserved as named byte spans by the descriptor
reader. A duplicate known property, invalid known-property size, trailing body
bytes, invalid enum, non-positive dimensions, impossible mip chain, overflow,
or payload-size mismatch is a hard error with a stable byte offset.

P2-20A.8 adds a separate, explicit recovery contract for a descriptor/payload
mip-count disagreement. It is disabled in the default binder and may only be
invoked for a hash-bound A.7 failure edge. The adapter enumerates the natural
mip chain for the declared format and dimensions and accepts only a payload
whose entire byte length ends at exactly one shorter mip-prefix boundary. It
never adds mips beyond the Package declaration. It preserves the
Package value as the declared count, records the inferred count as
`effective_mip_count`, and records `payload_complete_chain_contract` as the
basis. A partial mip, unexplained tail, zero count, unchanged count, or count
outside the natural chain remains rejected. DDS flags, caps, and header count
use the effective count; the original declared value remains visible in JSON.

P2-20A.13 adds the orthogonal, explicit
`parse_with_declared_mip_payload_prefix` contract for a longer payload. It is
also disabled in the default binder. The contract requires a non-zero stored
mip count equal to the canonical Package count. The input must be longer than
the byte prefix for that declared count, and its total length must end at the
single exact boundary of a longer complete natural mip chain. A partial tail,
shorter chain, unchanged extent, implicit count, unknown format or bytes beyond
the natural chain is rejected. Trailing complete mips do not increase
`effective_mip_count`; the Package declaration remains the effective count.

Every validated view records `input_payload_bytes`, `consumed_payload_bytes`,
`ignored_payload_bytes`, and `payload_extent_basis`. Strict and A.8 views use
`complete_input_payload`, consume the entire input, and ignore zero bytes. An
A.13 view uses `declared_mip_payload_prefix_contract`, consumes exactly the
declared mip prefix, and records the remaining complete mip bytes as ignored.
The legacy `payload_size` JSON field remains an alias for input payload bytes.

## 2. Texture formats

| Value | Legacy name | Payload layout | Alpha encoding | DDS mapping |
|---:|---|---|---|---|
| 0 | `TF_RGBA8` | D3D9 `A8R8G8B8`, byte order BGRA | straight 8-bit | BGRA8 masks |
| 1 | `TF_RGBA16F` | four little-endian binary16 channels, R/G/B/A | straight binary16 | DX10 `R16G16B16A16_FLOAT` |
| 2 | `TF_R32F` | little-endian IEEE-754 float | none | DX10 `R32_FLOAT` |
| 3 | `TF_DXT1` | BC1/DXT1 blocks | semantically opaque | `DXT1` |
| 4 | `TF_DXT1a` | BC1/DXT1 blocks | one-bit mask | `DXT1` |
| 5 | `TF_DXT3` | BC2/DXT3 blocks | explicit 4-bit | `DXT3` |
| 6 | `TF_DXT5` | BC3/DXT5 blocks | interpolated 8-bit | `DXT5` |

For block formats, one mip consumes
`max(1, ceil(width/4)) * max(1, ceil(height/4)) * block_bytes`, where block
bytes are 8 for DXT1/DXT1a and 16 for DXT3/DXT5. Uncompressed formats consume
width × height × 4 or 8 bytes. Each following mip clamps both dimensions to at
least one. Payload bytes are ordered largest mip to smallest mip with no header,
padding, checksum, encryption, or compression layer beyond the named block
format.

`alpha_encoding` reports the format capability. `alpha_coverage` is calculated
from decoded mip zero and is one of `opaque`, `transparent`, `binary_mask`, or
`translucent`. Keeping these separate prevents a DXT5 texture with all-opaque
pixels from being misreported as requiring blending.

## 3. Intermediate outputs

The offline exporter emits the same validated texture as:

- DDS, preserving the validated consumed payload extent and mip chain;
- PNG, deterministic RGBA8 mip-zero preview with filter 0 and stored DEFLATE;
- TGA, deterministic uncompressed 32-bit BGRA mip-zero preview, top-left origin;
- JSON metadata containing descriptor values, mip spans, alpha encoding and
  decoded alpha coverage, plus input, consumed and ignored payload extents.

For an A.13 view, DDS appends only the consumed declared-mip prefix. PNG and TGA
decode only mip zero, so ignored trailing complete mips cannot affect either
preview. The command-line exporter continues to call the strict parser and does
not auto-fallback to either recovery contract.

RGBA16F and R32F previews clamp finite channel values to `[0,1]`. Non-finite
float samples are rejected instead of silently producing platform-dependent
pixels. DDS remains the lossless intermediate for float formats and all mips.

## 4. Frozen real samples

| Object | Format | Size | Mips | qtx bytes | Role |
|---|---|---:|---:|---:|---|
| `texstone.WHZ_S_Dimian20_D` | DXT1 | 8×8 | 1 | 32 | minimum block boundary |
| `newscenc.dy_bx_xlys_01_D` | DXT5 | 4096×4096 | 13 | 22,369,648 | maximum/mip-chain boundary |
| `texparticle.FXH_T_toumingtu` | DXT5 | 16×16 | 1 | 256 | transparent candidate |
| `editorui.ToolBoxHighLight` | RGBA8 default | 512×512 | 1 | 1,048,576 | omitted-format/UI boundary |

The authoritative SHA-256 values for the Package files, qtx files, and legacy
source evidence are enforced by `Tests/Contract/Test-QtxTexture.ps1` and
recorded in `Data/BuildBaseline/p1-13-qtx-texture.json`.

## 5. Explicit non-goals

This reader does not load legacy D3D, infer a missing Package descriptor, create
UE assets, choose material blend modes, or mutate original files. Material
semantics and UE import policy remain later P1/P3 responsibilities.
