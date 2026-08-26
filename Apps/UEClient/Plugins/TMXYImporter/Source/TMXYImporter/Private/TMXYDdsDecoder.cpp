#include "TMXYDdsDecoder.h"

namespace
{
constexpr uint32 DdsMagic = 0x20534444U;
constexpr uint32 Dxt1 = 0x31545844U;
constexpr uint32 Dxt5 = 0x35545844U;

struct FRgba8
{
    uint8 R = 0;
    uint8 G = 0;
    uint8 B = 0;
    uint8 A = 255;
};

uint16 ReadU16(const uint8* bytes)
{
    return static_cast<uint16>(bytes[0]) | (static_cast<uint16>(bytes[1]) << 8U);
}

uint32 ReadU32(const uint8* bytes)
{
    return static_cast<uint32>(bytes[0]) | (static_cast<uint32>(bytes[1]) << 8U) |
           (static_cast<uint32>(bytes[2]) << 16U) | (static_cast<uint32>(bytes[3]) << 24U);
}

FRgba8 Decode565(const uint16 value)
{
    const uint32 red = (value >> 11U) & 31U;
    const uint32 green = (value >> 5U) & 63U;
    const uint32 blue = value & 31U;
    return {static_cast<uint8>((red * 255U + 15U) / 31U),
            static_cast<uint8>((green * 255U + 31U) / 63U),
            static_cast<uint8>((blue * 255U + 15U) / 31U), 255U};
}

FRgba8 Interpolate(const FRgba8& left, const FRgba8& right, const uint32 leftWeight,
                   const uint32 rightWeight, const uint32 denominator)
{
    return {static_cast<uint8>((leftWeight * left.R + rightWeight * right.R) / denominator),
            static_cast<uint8>((leftWeight * left.G + rightWeight * right.G) / denominator),
            static_cast<uint8>((leftWeight * left.B + rightWeight * right.B) / denominator), 255U};
}

void MakeColorPalette(const uint8* block, const bool forceFourColor, FRgba8 (&colors)[4])
{
    const uint16 color0 = ReadU16(block);
    const uint16 color1 = ReadU16(block + 2);
    colors[0] = Decode565(color0);
    colors[1] = Decode565(color1);
    if (forceFourColor || color0 > color1)
    {
        colors[2] = Interpolate(colors[0], colors[1], 2U, 1U, 3U);
        colors[3] = Interpolate(colors[0], colors[1], 1U, 2U, 3U);
    }
    else
    {
        colors[2] = Interpolate(colors[0], colors[1], 1U, 1U, 2U);
        colors[3] = {0U, 0U, 0U, 255U};
    }
}

void MakeDxt5AlphaPalette(const uint8* block, uint8 (&alpha)[8])
{
    alpha[0] = block[0];
    alpha[1] = block[1];
    if (alpha[0] > alpha[1])
    {
        for (uint32 index = 2; index < 8; ++index)
        {
            alpha[index] =
                static_cast<uint8>(((8U - index) * alpha[0] + (index - 1U) * alpha[1]) / 7U);
        }
        return;
    }
    for (uint32 index = 2; index < 6; ++index)
    {
        alpha[index] = static_cast<uint8>(((6U - index) * alpha[0] + (index - 1U) * alpha[1]) / 5U);
    }
    alpha[6] = 0;
    alpha[7] = 255;
}

void StorePixel(TArray<uint8>& output, const int32 mipOffset, const int32 width, const int32 height,
                const int32 x, const int32 y, const FRgba8& color)
{
    if (x >= width || y >= height)
    {
        return;
    }
    const int32 index = mipOffset + ((y * width + x) * 4);
    output[index] = color.B;
    output[index + 1] = color.G;
    output[index + 2] = color.R;
    output[index + 3] = color.A;
}

void DecodeBlock(const uint8* block, const bool isDxt5, const int32 blockX, const int32 blockY,
                 const int32 width, const int32 height, const int32 mipOffset,
                 TArray<uint8>& output)
{
    const uint8* colorBlock = block + (isDxt5 ? 8 : 0);
    FRgba8 colors[4];
    MakeColorPalette(colorBlock, isDxt5, colors);
    const uint32 colorIndices = ReadU32(colorBlock + 4);
    uint8 alpha[8]{};
    uint64 alphaIndices = 0;
    if (isDxt5)
    {
        MakeDxt5AlphaPalette(block, alpha);
        for (uint32 index = 0; index < 6; ++index)
        {
            alphaIndices |= static_cast<uint64>(block[2 + index]) << (index * 8U);
        }
    }
    for (int32 pixel = 0; pixel < 16; ++pixel)
    {
        FRgba8 color = colors[(colorIndices >> (pixel * 2)) & 3U];
        if (isDxt5)
        {
            color.A = alpha[(alphaIndices >> (pixel * 3)) & 7U];
        }
        StorePixel(output, mipOffset, width, height, blockX * 4 + pixel % 4, blockY * 4 + pixel / 4,
                   color);
    }
}

bool DecodeMip(const uint8* payload, const int32 payloadSize, const bool isDxt5, const int32 width,
               const int32 height, const int32 mipOffset, TArray<uint8>& output)
{
    const int32 blockBytes = isDxt5 ? 16 : 8;
    const int32 blocksWide = FMath::Max(1, (width + 3) / 4);
    const int32 blocksHigh = FMath::Max(1, (height + 3) / 4);
    if (payloadSize != blocksWide * blocksHigh * blockBytes)
    {
        return false;
    }
    int32 offset = 0;
    for (int32 y = 0; y < blocksHigh; ++y)
    {
        for (int32 x = 0; x < blocksWide; ++x)
        {
            DecodeBlock(payload + offset, isDxt5, x, y, width, height, mipOffset, output);
            offset += blockBytes;
        }
    }
    return true;
}
} // namespace

bool DecodeTMXYDds(const TArray<uint8>& bytes, FTMXYDecodedDds& decoded, FString& error)
{
    if (bytes.Num() < 128 || ReadU32(bytes.GetData()) != DdsMagic ||
        ReadU32(bytes.GetData() + 4) != 124U || ReadU32(bytes.GetData() + 76) != 32U)
    {
        error = TEXT("dds-header-invalid");
        return false;
    }
    const uint32 fourCc = ReadU32(bytes.GetData() + 84);
    if (fourCc != Dxt1 && fourCc != Dxt5)
    {
        error = TEXT("dds-format-unsupported");
        return false;
    }
    decoded.Width = static_cast<int32>(ReadU32(bytes.GetData() + 16));
    decoded.Height = static_cast<int32>(ReadU32(bytes.GetData() + 12));
    decoded.MipCount = FMath::Max(1, static_cast<int32>(ReadU32(bytes.GetData() + 28)));
    decoded.LegacyFormat = fourCc == Dxt1 ? TEXT("dxt1") : TEXT("dxt5");
    if (decoded.Width < 1 || decoded.Height < 1 || decoded.Width > 16384 ||
        decoded.Height > 16384 || decoded.MipCount > 15)
    {
        error = TEXT("dds-dimensions-invalid");
        return false;
    }
    int64 compressedBytes = 0;
    int64 decodedBytes = 0;
    int32 width = decoded.Width;
    int32 height = decoded.Height;
    const int32 blockBytes = fourCc == Dxt5 ? 16 : 8;
    for (int32 mip = 0; mip < decoded.MipCount; ++mip)
    {
        compressedBytes +=
            FMath::Max(1, (width + 3) / 4) * FMath::Max(1, (height + 3) / 4) * blockBytes;
        decodedBytes += static_cast<int64>(width) * height * 4;
        width = FMath::Max(1, width / 2);
        height = FMath::Max(1, height / 2);
    }
    if (compressedBytes != bytes.Num() - 128 || decodedBytes > MAX_int32)
    {
        error = TEXT("dds-payload-size-mismatch");
        return false;
    }
    decoded.Bgra8MipData.SetNumUninitialized(static_cast<int32>(decodedBytes));
    int32 sourceOffset = 128;
    int32 outputOffset = 0;
    width = decoded.Width;
    height = decoded.Height;
    for (int32 mip = 0; mip < decoded.MipCount; ++mip)
    {
        const int32 mipBytes =
            FMath::Max(1, (width + 3) / 4) * FMath::Max(1, (height + 3) / 4) * blockBytes;
        if (!DecodeMip(bytes.GetData() + sourceOffset, mipBytes, fourCc == Dxt5, width, height,
                       outputOffset, decoded.Bgra8MipData))
        {
            error = TEXT("dds-decode-failed");
            return false;
        }
        sourceOffset += mipBytes;
        outputOffset += width * height * 4;
        width = FMath::Max(1, width / 2);
        height = FMath::Max(1, height / 2);
    }
    return true;
}
