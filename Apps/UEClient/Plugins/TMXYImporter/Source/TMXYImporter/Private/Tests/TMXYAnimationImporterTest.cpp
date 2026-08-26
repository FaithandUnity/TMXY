#if WITH_DEV_AUTOMATION_TESTS

#include "Animation/AnimData/IAnimationDataModel.h"
#include "Animation/AnimSequence.h"
#include "Animation/Skeleton.h"
#include "Dom/JsonObject.h"
#include "HAL/FileManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "TMXYAnimGltfDecoder.h"
#include "TMXYAnimationManifest.h"
#include "TMXYImporterService.h"
#include "UObject/MetaData.h"

namespace
{
constexpr TCHAR ManifestPath[] = TEXT("Tests/Fixtures/UE/Animation/boy01-core-real/manifest.json");
constexpr TCHAR InvalidManifestPath[] =
    TEXT("Tests/Fixtures/UE/Animation/boy01-core-real/manifest-invalid-hash.json");
constexpr TCHAR InvalidPackage[] = TEXT("/Game/TMXY/Golden/Animations/A_Golden_Invalid_Hash");

FString ObjectPath(const FString& packageName)
{
    return packageName + TEXT(".") + FPackageName::GetLongPackageAssetName(packageName);
}

bool DecodeFixture(const FTMXYAnimationImportSpec& spec, FTMXYDecodedAnimSet& decoded,
                   FString& error)
{
    FString text;
    TArray<uint8> buffer;
    return FFileHelper::LoadFileToString(text, *spec.GltfPath) &&
           FFileHelper::LoadFileToArray(buffer, *spec.BufferPath) &&
           DecodeTMXYAnimGltf(text, buffer, spec.BufferRelativePath, spec.ExpectedBoneCount,
                              spec.Clips.Num(), decoded, error);
}

struct FClipObservation
{
    bool bKeysMatch = false;
    bool bRootTrackPreserved = false;
    bool bLoopPolicyPreserved = false;
    double RootTranslationMeters = 0.0;
    double MaximumEndpointTranslationMeters = 0.0;
    double MaximumEndpointRotationDegrees = 0.0;
};

double RotationDegrees(const FQuat4f& first, const FQuat4f& last)
{
    const double dot = FMath::Clamp(FMath::Abs(static_cast<double>(first | last)), 0.0, 1.0);
    return FMath::RadiansToDegrees(2.0 * FMath::Acos(dot));
}

FClipObservation InspectClip(const UAnimSequence& sequence, const FTMXYDecodedAnimSet& decoded,
                             const int32 clipIndex)
{
    const IAnimationDataModel* model = sequence.GetDataModel();
    const FTMXYDecodedAnimClip& expected = decoded.Clips[clipIndex];
    FClipObservation observation;
    observation.bKeysMatch = model != nullptr;
    for (int32 trackIndex = 0; model != nullptr && trackIndex < expected.Tracks.Num(); ++trackIndex)
    {
        TArray<FTransform> transforms;
        model->GetBoneTrackTransforms(FName(*decoded.BoneNames[trackIndex]), transforms);
        const FTMXYAnimTrack& source = expected.Tracks[trackIndex];
        observation.bKeysMatch &= transforms.Num() == source.PositionsCm.Num();
        for (int32 frame = 0; frame < transforms.Num() && frame < source.PositionsCm.Num(); ++frame)
        {
            const FVector expectedPosition(source.PositionsCm[frame]);
            const FQuat expectedRotation(source.Rotations[frame]);
            observation.bKeysMatch &=
                transforms[frame].GetTranslation().Equals(expectedPosition, 0.001) &&
                FMath::Abs(transforms[frame].GetRotation() | expectedRotation) >= 0.999999 &&
                transforms[frame].GetScale3D().Equals(FVector::OneVector, 0.000001) &&
                !transforms[frame].ContainsNaN();
        }
        const double translationMeters =
            FVector3f::Distance(source.PositionsCm[0], source.PositionsCm.Last()) / 100.0;
        observation.MaximumEndpointTranslationMeters =
            FMath::Max(observation.MaximumEndpointTranslationMeters, translationMeters);
        observation.MaximumEndpointRotationDegrees =
            FMath::Max(observation.MaximumEndpointRotationDegrees,
                       RotationDegrees(source.Rotations[0], source.Rotations.Last()));
    }
    const FTMXYAnimTrack& root = expected.Tracks[0];
    observation.RootTranslationMeters =
        FVector3f::Distance(root.PositionsCm[0], root.PositionsCm.Last()) / 100.0;
    observation.bRootTrackPreserved = !sequence.bEnableRootMotion && model != nullptr &&
                                      model->IsValidBoneTrackName(FName(*decoded.BoneNames[0]));
    FMetaData& metadata = sequence.GetPackage()->GetMetaData();
    observation.bLoopPolicyPreserved =
        metadata.GetValue(&sequence, TEXT("TMXY.LegacySelfLoop")) == TEXT("false") &&
        metadata.GetValue(&sequence, TEXT("TMXY.RootMotionPolicy")) ==
            TEXT("preserved-root-track-not-extracted");
    return observation;
}

bool NearlyEqual(const double actual, const double expected, const double tolerance)
{
    return FMath::Abs(actual - expected) <= tolerance;
}

bool VerifySequenceContract(const UAnimSequence& sequence, const FTMXYAnimationImportSpec& spec,
                            const FTMXYDecodedAnimSet& decoded, const int32 clipIndex,
                            FClipObservation& observation)
{
    const FTMXYAnimationClipSpec& expected = spec.Clips[clipIndex];
    const IAnimationDataModel* model = sequence.GetDataModel();
    if (model == nullptr)
    {
        return false;
    }
    TArray<FName> names;
    model->GetBoneTrackNames(names);
    observation = InspectClip(sequence, decoded, clipIndex);
    const bool expectedMoving = observation.RootTranslationMeters > 0.000001;
    return model->GetFrameRate() ==
               FFrameRate(spec.SampleRateNumerator, spec.SampleRateDenominator) &&
           model->GetNumberOfFrames() == expected.ExpectedFrameCount - 1 &&
           model->GetNumberOfKeys() == expected.ExpectedFrameCount &&
           model->GetNumBoneTracks() == expected.ExpectedTrackCount &&
           names.Num() == expected.ExpectedTrackCount && observation.bKeysMatch &&
           observation.bRootTrackPreserved && observation.bLoopPolicyPreserved &&
           expectedMoving == expected.bExpectedRootMoving &&
           NearlyEqual(model->GetPlayLength(), expected.ExpectedSampledDurationSeconds, 0.000001) &&
           NearlyEqual(observation.RootTranslationMeters,
                       expected.ExpectedRootTranslationDistanceMeters, 0.000001) &&
           NearlyEqual(observation.MaximumEndpointTranslationMeters,
                       expected.ExpectedMaximumEndpointTranslationMeters, 0.000001) &&
           NearlyEqual(observation.MaximumEndpointRotationDegrees,
                       expected.ExpectedMaximumEndpointRotationDegrees, 0.005);
}

bool ReadPackages(const FTMXYAnimationImportSpec& spec, TArray<TArray<uint8>>& bytes)
{
    bytes.SetNum(spec.Clips.Num());
    bool succeeded = true;
    for (int32 index = 0; index < spec.Clips.Num(); ++index)
    {
        const FString filename = FPackageName::LongPackageNameToFilename(
            spec.Clips[index].PackageName, FPackageName::GetAssetPackageExtension());
        succeeded &= FFileHelper::LoadFileToArray(bytes[index], *filename);
    }
    return succeeded;
}

TSharedPtr<FJsonValue> MakeObservation(const FTMXYAnimationClipSpec& spec,
                                       const FClipObservation& observation)
{
    TSharedRef<FJsonObject> value = MakeShared<FJsonObject>();
    value->SetStringField(TEXT("source_name"), spec.SourceName);
    value->SetStringField(TEXT("package_name"), spec.PackageName);
    value->SetNumberField(TEXT("source_index"), spec.SourceIndex);
    value->SetNumberField(TEXT("frame_count"), spec.ExpectedFrameCount);
    value->SetNumberField(TEXT("track_count"), spec.ExpectedTrackCount);
    value->SetNumberField(TEXT("sampled_duration_seconds"), spec.ExpectedSampledDurationSeconds);
    value->SetNumberField(TEXT("legacy_loop_period_seconds"), spec.ExpectedLegacyLoopPeriodSeconds);
    value->SetBoolField(TEXT("legacy_self_loop"), spec.bLegacySelfLoop);
    value->SetBoolField(TEXT("all_keys_match_interchange"), observation.bKeysMatch);
    value->SetBoolField(TEXT("root_track_preserved"), observation.bRootTrackPreserved);
    value->SetBoolField(TEXT("loop_policy_preserved"), observation.bLoopPolicyPreserved);
    value->SetNumberField(TEXT("root_translation_distance_meters"),
                          observation.RootTranslationMeters);
    value->SetNumberField(TEXT("maximum_endpoint_translation_delta_meters"),
                          observation.MaximumEndpointTranslationMeters);
    value->SetNumberField(TEXT("maximum_endpoint_rotation_delta_degrees"),
                          observation.MaximumEndpointRotationDegrees);
    return MakeShared<FJsonValueObject>(value);
}

} // namespace

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FTMXYAnimationImporterTest, "TMXY.Importer.Animation",
                                 EAutomationTestFlags::EditorContext |
                                     EAutomationTestFlags::EngineFilter)

bool FTMXYAnimationImporterTest::RunTest(const FString& parameters)
{
    static_cast<void>(parameters);
    const FString rebuildRoot =
        FPaths::ConvertRelativePathToFull(FPaths::Combine(FPaths::ProjectDir(), TEXT("../..")));
    FTMXYImporterService service(rebuildRoot);
    TestEqual(TEXT("glTF routing plus terrain keep three production format handlers"),
              service.GetRegisteredImporterCount(), 3);

    const FTMXYImportRequest request{TEXT("boy01-core-real"), ManifestPath,
                                     ETMXYImportMode::SingleFixture};
    FTMXYAnimationImportSpec spec;
    FString specError;
    TestTrue(TEXT("Animation manifest and all hashes validate"),
             ReadTMXYAnimationSpec(rebuildRoot, request, TEXT("animation-gltf"), spec, specError));
    TestEqual(TEXT("Animation manifest error"), specError, FString());
    if (!specError.IsEmpty())
    {
        return false;
    }
    FTMXYDecodedAnimSet decoded;
    FString decodeError;
    TestTrue(TEXT("Authoritative animation glTF decodes"),
             DecodeFixture(spec, decoded, decodeError));
    TestEqual(TEXT("Animation glTF decode error"), decodeError, FString());
    if (!decodeError.IsEmpty())
    {
        return false;
    }
    TestEqual(TEXT("Animation set has Boy01 bone count"), decoded.BoneNames.Num(), 80);
    TestEqual(TEXT("Animation set has selected clip count"), decoded.Clips.Num(), 3);

    const FTMXYImportRequest invalidRequest{TEXT("boy01-animation-invalid"), InvalidManifestPath,
                                            ETMXYImportMode::SingleFixture};
    const FTMXYImportItemResult invalid =
        service.ImportArtifact(invalidRequest, TEXT("animation-gltf"));
    TestFalse(TEXT("Animation artifact hash mismatch is rejected"), invalid.bSucceeded);
    TestEqual(TEXT("Animation hash mismatch has stable error"), invalid.ErrorCode,
              FString(TEXT("artifact-integrity-mismatch")));
    TestFalse(TEXT("Invalid animation creates no package"),
              FPackageName::DoesPackageExist(InvalidPackage));

    const FTMXYImportItemResult imported = service.ImportArtifact(request, TEXT("animation-gltf"));
    TestTrue(TEXT("Boy01 selected animations import"), imported.bSucceeded);
    TestEqual(TEXT("Animation import error"), imported.ErrorCode, FString());
    TestEqual(TEXT("Animation import produces three assets"), imported.ImportedAssetCount, 3);

    TArray<UAnimSequence*> sequences;
    TArray<FClipObservation> observations;
    bool contractsPassed = true;
    for (int32 index = 0; index < spec.Clips.Num(); ++index)
    {
        UAnimSequence* sequence =
            LoadObject<UAnimSequence>(nullptr, *ObjectPath(spec.Clips[index].PackageName));
        sequences.Add(sequence);
        TestNotNull(
            *FString::Printf(TEXT("Animation %s is loadable"), *spec.Clips[index].SourceName),
            sequence);
        FClipObservation observation;
        const bool passed = sequence != nullptr &&
                            VerifySequenceContract(*sequence, spec, decoded, index, observation);
        observations.Add(observation);
        TestTrue(*FString::Printf(
                     TEXT("Animation %s preserves all keys, timing, root and loop metadata"),
                     *spec.Clips[index].SourceName),
                 passed);
        contractsPassed &= passed;
    }

    TArray<TArray<uint8>> before;
    TestTrue(TEXT("Animation packages readable before reimport"), ReadPackages(spec, before));
    bool reimportPassed = true;
    for (const FTMXYAnimationClipSpec& clip : spec.Clips)
    {
        const FTMXYReimportRequest reimportRequest{TEXT("khronos.gltf-json"), clip.PackageName,
                                                   ManifestPath, TEXT("animation-gltf")};
        TestTrue(TEXT("Animation reimport accepts canonical target"),
                 service.EvaluateReimport(reimportRequest).bCanReimport);
        reimportPassed &= service.Reimport(reimportRequest).bSucceeded;
    }
    TestTrue(TEXT("All animation reimports succeed"), reimportPassed);
    TArray<TArray<uint8>> after;
    const bool afterReadable = ReadPackages(spec, after);
    TestTrue(TEXT("Animation packages readable after reimport"), afterReadable);
    const bool bytesUnchanged = before == after;
    TestTrue(TEXT("Animation reimport preserves every package byte"), bytesUnchanged);

    const FString reportPath = FPaths::Combine(
        FPaths::ProjectSavedDir(), TEXT("Automation/TMXYImporter/p1-25-animation-report.json"));
    TSharedRef<FJsonObject> report = MakeShared<FJsonObject>();
    report->SetStringField(TEXT("schema"), TEXT("tmxy.ue.animation-import-report"));
    report->SetNumberField(TEXT("schema_version"), 1);
    report->SetStringField(TEXT("report_version"), TEXT("1.0.0"));
    report->SetStringField(TEXT("handler_format_id"), TEXT("khronos.gltf-json"));
    report->SetStringField(TEXT("fixture_id"), TEXT("boy01-core-real"));
    report->SetStringField(TEXT("manifest_path"), ManifestPath);
    report->SetStringField(TEXT("manifest_sha256"), imported.ManifestSha256);
    report->SetNumberField(TEXT("imported_asset_count"), imported.ImportedAssetCount);
    report->SetNumberField(TEXT("bone_count"), decoded.BoneNames.Num());
    report->SetNumberField(TEXT("sample_rate_numerator"), spec.SampleRateNumerator);
    report->SetNumberField(TEXT("sample_rate_denominator"), spec.SampleRateDenominator);
    report->SetStringField(TEXT("root_motion_policy"), TEXT("preserved-root-track-not-extracted"));
    report->SetStringField(TEXT("legacy_loop_policy"),
                           TEXT("preserve-metadata-no-forced-loop-flag"));
    report->SetBoolField(TEXT("invalid_hash_rejected"), !invalid.bSucceeded);
    report->SetBoolField(TEXT("invalid_hash_asset_created"),
                         FPackageName::DoesPackageExist(InvalidPackage));
    report->SetBoolField(TEXT("all_clip_contracts_passed"), contractsPassed);
    report->SetBoolField(TEXT("reimport_passed"), reimportPassed);
    report->SetBoolField(TEXT("reimport_bytes_unchanged"), bytesUnchanged);
    TArray<TSharedPtr<FJsonValue>> clipReports;
    for (int32 index = 0; index < spec.Clips.Num(); ++index)
    {
        clipReports.Add(MakeObservation(spec.Clips[index], observations[index]));
    }
    report->SetArrayField(TEXT("clips"), clipReports);
    FString serialized;
    const TSharedRef<TJsonWriter<>> writer = TJsonWriterFactory<>::Create(&serialized);
    const bool serializedOk = FJsonSerializer::Serialize(report, writer);
    serialized.ReplaceInline(TEXT("\r\n"), TEXT("\n"));
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(reportPath), true);
    const bool reportWritten =
        serializedOk &&
        FFileHelper::SaveStringToFile(serialized + TEXT("\n"), *reportPath,
                                      FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
    TestTrue(TEXT("Animation import report is written"), reportWritten);
    return !HasAnyErrors();
}

#endif
