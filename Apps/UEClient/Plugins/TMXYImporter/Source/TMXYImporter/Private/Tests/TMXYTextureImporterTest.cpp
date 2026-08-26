#if WITH_DEV_AUTOMATION_TESTS

#include "Dom/JsonObject.h"
#include "Engine/Texture2D.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "TMXYImporterService.h"

namespace
{
constexpr TCHAR OpaqueManifest[] = TEXT("Tests/Fixtures/UE/Texture/opaque-dxt1/manifest.json");
constexpr TCHAR TransparentManifest[] =
    TEXT("Tests/Fixtures/UE/Texture/transparent-dxt5/manifest.json");
constexpr TCHAR MultiMipManifest[] = TEXT("Tests/Fixtures/UE/Texture/multi-mip-dxt1/manifest.json");
constexpr TCHAR InvalidHashManifest[] =
    TEXT("Tests/Fixtures/UE/Texture/opaque-dxt1/manifest-invalid-hash.json");
constexpr TCHAR OpaquePackage[] = TEXT("/Game/TMXY/Golden/Textures/T_Golden_Opaque_DXT1");
constexpr TCHAR TransparentPackage[] = TEXT("/Game/TMXY/Golden/Textures/T_Golden_Transparent_DXT5");
constexpr TCHAR MultiMipPackage[] = TEXT("/Game/TMXY/Golden/Textures/T_Golden_MultiMip_DXT1");
constexpr TCHAR InvalidPackage[] = TEXT("/Game/TMXY/Golden/Textures/T_Golden_Invalid_Hash");

FString ObjectPath(const FString& packageName)
{
    return packageName + TEXT(".") + FPackageName::GetLongPackageAssetName(packageName);
}

UTexture2D* LoadTexture(const FString& packageName)
{
    return LoadObject<UTexture2D>(nullptr, *ObjectPath(packageName));
}

TSharedRef<FJsonObject> MakeObservation(const TCHAR* fixtureId, const TCHAR* manifestPath,
                                        const FTMXYImportItemResult& result, UTexture2D* texture,
                                        const TCHAR* legacyFormat, const TCHAR* alphaCoverage,
                                        const TCHAR* expectedCookedFormat)
{
    TSharedRef<FJsonObject> observation = MakeShared<FJsonObject>();
    observation->SetStringField(TEXT("fixture_id"), fixtureId);
    observation->SetStringField(TEXT("manifest_path"), manifestPath);
    observation->SetStringField(TEXT("manifest_sha256"), result.ManifestSha256);
    observation->SetStringField(TEXT("artifact_id"), TEXT("texture-payload"));
    observation->SetStringField(TEXT("package_name"), result.OutputPackageName);
    observation->SetStringField(TEXT("legacy_format"), legacyFormat);
    observation->SetStringField(TEXT("alpha_coverage"), alphaCoverage);
    observation->SetNumberField(TEXT("width"), texture->Source.GetSizeX());
    observation->SetNumberField(TEXT("height"), texture->Source.GetSizeY());
    observation->SetNumberField(TEXT("source_mip_count"), texture->Source.GetNumMips());
    observation->SetBoolField(TEXT("srgb"), texture->SRGB);
    observation->SetBoolField(TEXT("compression_no_alpha"), texture->CompressionNoAlpha);
    observation->SetStringField(TEXT("source_format"), TEXT("TSF_BGRA8"));
    observation->SetStringField(TEXT("expected_cooked_format"), expectedCookedFormat);
    return observation;
}

bool WriteReport(const FString& outputPath, int32 beforeCount,
                 const FTMXYImportItemResult& invalidResult,
                 const FTMXYImportItemResult& reimportResult, bool reimportPackageBytesUnchanged,
                 const TArray<TSharedPtr<FJsonValue>>& observations)
{
    TSharedRef<FJsonObject> report = MakeShared<FJsonObject>();
    report->SetStringField(TEXT("schema"), TEXT("tmxy.ue.texture-import-report"));
    report->SetNumberField(TEXT("schema_version"), 1);
    report->SetStringField(TEXT("report_version"), TEXT("1.0.0"));
    report->SetStringField(TEXT("handler_format_id"), TEXT("microsoft.dds"));
    report->SetNumberField(TEXT("before_asset_count"), beforeCount);
    report->SetNumberField(TEXT("after_asset_count"), observations.Num());
    report->SetNumberField(TEXT("imported_asset_count"), observations.Num());
    report->SetBoolField(TEXT("invalid_hash_rejected"),
                         !invalidResult.bSucceeded &&
                             invalidResult.ErrorCode == TEXT("artifact-integrity-mismatch"));
    report->SetBoolField(TEXT("invalid_hash_asset_created"),
                         FPackageName::DoesPackageExist(InvalidPackage));
    report->SetBoolField(TEXT("reimport_passed"), reimportResult.bSucceeded);
    report->SetBoolField(TEXT("reimport_package_bytes_unchanged"), reimportPackageBytesUnchanged);
    report->SetArrayField(TEXT("textures"), observations);
    FString serialized;
    const TSharedRef<TJsonWriter<>> writer = TJsonWriterFactory<>::Create(&serialized);
    if (!FJsonSerializer::Serialize(report, writer))
    {
        return false;
    }
    serialized.ReplaceInline(TEXT("\r\n"), TEXT("\n"));
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(outputPath), true);
    return FFileHelper::SaveStringToFile(serialized + TEXT("\n"), *outputPath,
                                         FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
}
} // namespace

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FTMXYTextureImporterTest, "TMXY.Importer.Texture",
                                 EAutomationTestFlags::EditorContext |
                                     EAutomationTestFlags::EngineFilter)

bool FTMXYTextureImporterTest::RunTest(const FString& parameters)
{
    static_cast<void>(parameters);
    const FString rebuildRoot =
        FPaths::ConvertRelativePathToFull(FPaths::Combine(FPaths::ProjectDir(), TEXT("../..")));
    FTMXYImporterService service(rebuildRoot);
    TestEqual(TEXT("Three production importers are registered"),
              service.GetRegisteredImporterCount(), 3);

    const int32 beforeCount =
        static_cast<int32>(FPackageName::DoesPackageExist(OpaquePackage)) +
        static_cast<int32>(FPackageName::DoesPackageExist(TransparentPackage)) +
        static_cast<int32>(FPackageName::DoesPackageExist(MultiMipPackage));
    const FTMXYImportRequest invalidRequest{TEXT("invalid-hash"), InvalidHashManifest,
                                            ETMXYImportMode::SingleFixture};
    const FTMXYImportItemResult invalid =
        service.ImportArtifact(invalidRequest, TEXT("texture-payload"));
    TestFalse(TEXT("Artifact hash mismatch is rejected"), invalid.bSucceeded);
    TestEqual(TEXT("Artifact hash mismatch has stable error"), invalid.ErrorCode,
              FString(TEXT("artifact-integrity-mismatch")));
    TestFalse(TEXT("Invalid hash creates no package"),
              FPackageName::DoesPackageExist(InvalidPackage));

    const FTMXYImportRequest opaqueRequest{TEXT("opaque-dxt1"), OpaqueManifest,
                                           ETMXYImportMode::SingleFixture};
    const FTMXYImportRequest transparentRequest{TEXT("transparent-dxt5"), TransparentManifest,
                                                ETMXYImportMode::SingleFixture};
    const FTMXYImportRequest multiMipRequest{TEXT("multi-mip-dxt1"), MultiMipManifest,
                                             ETMXYImportMode::SingleFixture};
    const FTMXYImportItemResult opaque =
        service.ImportArtifact(opaqueRequest, TEXT("texture-payload"));
    const FTMXYImportItemResult transparent =
        service.ImportArtifact(transparentRequest, TEXT("texture-payload"));
    const FTMXYImportItemResult multiMip =
        service.ImportArtifact(multiMipRequest, TEXT("texture-payload"));
    TestTrue(TEXT("Opaque DXT1 imports"), opaque.bSucceeded);
    TestEqual(TEXT("Opaque import error"), opaque.ErrorCode, FString());
    TestTrue(TEXT("Transparent DXT5 imports"), transparent.bSucceeded);
    TestEqual(TEXT("Transparent import error"), transparent.ErrorCode, FString());
    TestTrue(TEXT("Multi-mip DXT1 imports"), multiMip.bSucceeded);
    UTexture2D* opaqueTexture = LoadTexture(OpaquePackage);
    UTexture2D* transparentTexture = LoadTexture(TransparentPackage);
    UTexture2D* multiMipTexture = LoadTexture(MultiMipPackage);
    TestNotNull(TEXT("Opaque texture is loadable"), opaqueTexture);
    TestNotNull(TEXT("Transparent texture is loadable"), transparentTexture);
    TestNotNull(TEXT("Multi-mip texture is loadable"), multiMipTexture);
    if (opaqueTexture == nullptr || transparentTexture == nullptr || multiMipTexture == nullptr)
    {
        return false;
    }

    opaqueTexture->FinishCachePlatformData();
    transparentTexture->FinishCachePlatformData();
    multiMipTexture->FinishCachePlatformData();
    TestEqual(TEXT("Opaque width"), opaqueTexture->Source.GetSizeX(), int64{8});
    TestEqual(TEXT("Opaque height"), opaqueTexture->Source.GetSizeY(), int64{8});
    TestEqual(TEXT("Opaque mip count"), opaqueTexture->Source.GetNumMips(), 1);
    TestTrue(TEXT("Opaque texture is sRGB"), opaqueTexture->SRGB);
    TestTrue(TEXT("Opaque texture disables alpha compression"),
             static_cast<bool>(opaqueTexture->CompressionNoAlpha));
    TestEqual(TEXT("Opaque decoded source format"), opaqueTexture->Source.GetFormat(), TSF_BGRA8);
    TestEqual(TEXT("Transparent width"), transparentTexture->Source.GetSizeX(), int64{16});
    TestEqual(TEXT("Transparent height"), transparentTexture->Source.GetSizeY(), int64{16});
    TestEqual(TEXT("Transparent mip count"), transparentTexture->Source.GetNumMips(), 1);
    TestTrue(TEXT("Transparent texture is sRGB"), transparentTexture->SRGB);
    TestFalse(TEXT("Transparent texture retains alpha"),
              static_cast<bool>(transparentTexture->CompressionNoAlpha));
    TestEqual(TEXT("Transparent decoded source format"), transparentTexture->Source.GetFormat(),
              TSF_BGRA8);
    TestEqual(TEXT("Multi-mip width"), multiMipTexture->Source.GetSizeX(), int64{8});
    TestEqual(TEXT("Multi-mip height"), multiMipTexture->Source.GetSizeY(), int64{8});
    TestEqual(TEXT("Complete source mip chain"), multiMipTexture->Source.GetNumMips(), 4);
    TestEqual(TEXT("Multi-mip decoded source format"), multiMipTexture->Source.GetFormat(),
              TSF_BGRA8);
    TestTrue(TEXT("Multi-mip texture is sRGB"), multiMipTexture->SRGB);

    const FTMXYReimportRequest reimportRequest{TEXT("microsoft.dds"), TransparentPackage,
                                               TransparentManifest, TEXT("texture-payload")};
    TestTrue(TEXT("Texture reimport boundary accepts canonical target"),
             service.EvaluateReimport(reimportRequest).bCanReimport);
    const FString transparentFilename = FPackageName::LongPackageNameToFilename(
        TransparentPackage, FPackageName::GetAssetPackageExtension());
    TArray<uint8> transparentBytesBefore;
    const bool loadedBefore =
        FFileHelper::LoadFileToArray(transparentBytesBefore, *transparentFilename);
    TestTrue(TEXT("Texture package bytes are readable before reimport"), loadedBefore);
    const FTMXYImportItemResult reimport = service.Reimport(reimportRequest);
    TestTrue(TEXT("Texture reimport succeeds"), reimport.bSucceeded);
    TestEqual(TEXT("Texture reimport error"), reimport.ErrorCode, FString());
    TArray<uint8> transparentBytesAfter;
    const bool loadedAfter =
        FFileHelper::LoadFileToArray(transparentBytesAfter, *transparentFilename);
    TestTrue(TEXT("Texture package bytes are readable after reimport"), loadedAfter);
    const bool reimportPackageBytesUnchanged =
        loadedBefore && loadedAfter && transparentBytesBefore == transparentBytesAfter;
    TestTrue(TEXT("Texture reimport preserves package bytes"), reimportPackageBytesUnchanged);

    TArray<TSharedPtr<FJsonValue>> observations;
    observations.Add(MakeShared<FJsonValueObject>(
        MakeObservation(TEXT("opaque-dxt1"), OpaqueManifest, opaque, opaqueTexture, TEXT("dxt1"),
                        TEXT("opaque"), TEXT("PF_DXT1"))));
    observations.Add(MakeShared<FJsonValueObject>(
        MakeObservation(TEXT("transparent-dxt5"), TransparentManifest, transparent,
                        transparentTexture, TEXT("dxt5"), TEXT("transparent"), TEXT("PF_DXT5"))));
    observations.Add(MakeShared<FJsonValueObject>(
        MakeObservation(TEXT("multi-mip-dxt1"), MultiMipManifest, multiMip, multiMipTexture,
                        TEXT("dxt1"), TEXT("opaque"), TEXT("PF_DXT1"))));
    const FString reportPath = FPaths::Combine(
        FPaths::ProjectSavedDir(), TEXT("Automation/TMXYImporter/p1-22-texture-report.json"));
    TestTrue(TEXT("Texture import report is written"),
             WriteReport(reportPath, beforeCount, invalid, reimport, reimportPackageBytesUnchanged,
                         observations));
    return !HasAnyErrors();
}

#endif
