#include "TMXYAnimationImporter.h"

#include "Animation/AnimData/IAnimationDataController.h"
#include "Animation/AnimData/IAnimationDataModel.h"
#include "Animation/AnimSequence.h"
#include "Animation/Skeleton.h"
#include "Dom/JsonObject.h"
#include "Engine/SkeletalMesh.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "TMXYAnimGltfDecoder.h"
#include "TMXYAnimationManifest.h"
#include "UObject/MetaData.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"

namespace
{
constexpr TCHAR AnimationRoot[] = TEXT("/Game/TMXY/Golden/Animations/");
constexpr TCHAR ManifestHashKey[] = TEXT("TMXY.ManifestSha256");
constexpr TCHAR ImporterVersionKey[] = TEXT("TMXY.AnimationImporterVersion");
constexpr TCHAR SourceNameKey[] = TEXT("TMXY.LegacyAnimationName");
constexpr TCHAR SourceIndexKey[] = TEXT("TMXY.LegacyAnimationIndex");
constexpr TCHAR LegacySelfLoopKey[] = TEXT("TMXY.LegacySelfLoop");
constexpr TCHAR RootMotionPolicyKey[] = TEXT("TMXY.RootMotionPolicy");
constexpr TCHAR ImporterVersion[] = TEXT("1");
constexpr TCHAR RootMotionPolicy[] = TEXT("preserved-root-track-not-extracted");

struct FLoadedDependencies
{
    USkeleton* Skeleton = nullptr;
    USkeletalMesh* SkeletalMesh = nullptr;
};

FTMXYImportItemResult MakeFailure(const FTMXYImportRequest& request, const FString& error)
{
    FTMXYImportItemResult result;
    result.RequestId = request.RequestId;
    result.RelativeManifestPath = request.RelativeManifestPath;
    result.Status = TEXT("failed");
    result.ErrorCode = error;
    return result;
}

FString ObjectPath(const FString& packageName)
{
    return packageName + TEXT(".") + FPackageName::GetLongPackageAssetName(packageName);
}

bool ValidateMetadata(const FTMXYAnimationImportSpec& spec, FString& error)
{
    FString text;
    TSharedPtr<FJsonObject> root;
    const TArray<TSharedPtr<FJsonValue>>* clips = nullptr;
    double boneCount = 0.0;
    double sampleRate = 0.0;
    FString assetKind;
    FString rootMotionPolicy;
    FString quaternionPolicy;
    if (!FFileHelper::LoadFileToString(text, *spec.MetadataPath))
    {
        error = TEXT("animation-metadata-read-failed");
        return false;
    }
    const TSharedRef<TJsonReader<>> reader = TJsonReaderFactory<>::Create(text);
    if (!FJsonSerializer::Deserialize(reader, root) || !root.IsValid() ||
        !root->TryGetStringField(TEXT("asset_kind"), assetKind) ||
        assetKind != TEXT("animation_set") ||
        !root->TryGetNumberField(TEXT("skeleton_bone_count"), boneCount) ||
        boneCount != spec.ExpectedBoneCount ||
        !root->TryGetNumberField(TEXT("sample_rate_hz"), sampleRate) ||
        sampleRate != static_cast<double>(spec.SampleRateNumerator) / spec.SampleRateDenominator ||
        !root->TryGetStringField(TEXT("root_motion_policy"), rootMotionPolicy) ||
        rootMotionPolicy != RootMotionPolicy ||
        !root->TryGetStringField(TEXT("quaternion_policy"), quaternionPolicy) ||
        quaternionPolicy != TEXT("normalized-adjacent-hemisphere-continuity") ||
        !root->TryGetArrayField(TEXT("clips"), clips) || clips->Num() != spec.Clips.Num())
    {
        error = TEXT("animation-metadata-contract-invalid");
        return false;
    }
    for (int32 index = 0; index < clips->Num(); ++index)
    {
        const TSharedPtr<FJsonObject> clip = (*clips)[index]->AsObject();
        const FTMXYAnimationClipSpec& expected = spec.Clips[index];
        FString name;
        double sourceIndex = -1.0;
        double frames = 0.0;
        double tracks = 0.0;
        bool selfLoop = true;
        if (!clip.IsValid() || !clip->TryGetStringField(TEXT("name"), name) ||
            name != expected.SourceName ||
            !clip->TryGetNumberField(TEXT("source_index"), sourceIndex) ||
            sourceIndex != expected.SourceIndex ||
            !clip->TryGetNumberField(TEXT("frame_count"), frames) ||
            frames != expected.ExpectedFrameCount ||
            !clip->TryGetNumberField(TEXT("track_count"), tracks) ||
            tracks != expected.ExpectedTrackCount ||
            !clip->TryGetBoolField(TEXT("self_loop"), selfLoop) ||
            selfLoop != expected.bLegacySelfLoop)
        {
            error = TEXT("animation-metadata-clip-mismatch");
            return false;
        }
    }
    return true;
}

bool ValidateDecoded(const FTMXYAnimationImportSpec& spec, const FTMXYDecodedAnimSet& decoded,
                     FString& error)
{
    if (decoded.BoneNames.Num() != spec.ExpectedBoneCount ||
        decoded.Clips.Num() != spec.Clips.Num())
    {
        error = TEXT("animation-decoded-count-mismatch");
        return false;
    }
    const double frameSeconds =
        static_cast<double>(spec.SampleRateDenominator) / spec.SampleRateNumerator;
    for (int32 clipIndex = 0; clipIndex < decoded.Clips.Num(); ++clipIndex)
    {
        const FTMXYDecodedAnimClip& clip = decoded.Clips[clipIndex];
        const FTMXYAnimationClipSpec& expected = spec.Clips[clipIndex];
        if (clip.Name != expected.SourceName || clip.Times.Num() != expected.ExpectedFrameCount ||
            clip.Tracks.Num() != expected.ExpectedTrackCount ||
            !FMath::IsNearlyEqual(static_cast<double>(clip.Times.Last()),
                                  expected.ExpectedSampledDurationSeconds, 0.000001))
        {
            error = TEXT("animation-decoded-clip-mismatch");
            return false;
        }
        for (int32 frame = 0; frame < clip.Times.Num(); ++frame)
        {
            const double expectedTime = frame * frameSeconds;
            if (!FMath::IsNearlyEqual(static_cast<double>(clip.Times[frame]), expectedTime,
                                      0.000001))
            {
                error = TEXT("animation-sample-time-mismatch");
                return false;
            }
        }
        for (const FTMXYAnimTrack& track : clip.Tracks)
        {
            if (track.PositionsCm.Num() != clip.Times.Num() ||
                track.Rotations.Num() != clip.Times.Num())
            {
                error = TEXT("animation-track-key-count-mismatch");
                return false;
            }
        }
    }
    return true;
}

bool LoadDependencies(const FTMXYAnimationImportSpec& spec, const FTMXYDecodedAnimSet& decoded,
                      FLoadedDependencies& dependencies, FString& error)
{
    dependencies.Skeleton = LoadObject<USkeleton>(nullptr, *ObjectPath(spec.SkeletonPackageName));
    dependencies.SkeletalMesh =
        LoadObject<USkeletalMesh>(nullptr, *ObjectPath(spec.SkeletalMeshPackageName));
    if (dependencies.Skeleton == nullptr || dependencies.SkeletalMesh == nullptr ||
        dependencies.SkeletalMesh->GetSkeleton() != dependencies.Skeleton)
    {
        error = TEXT("animation-skeleton-dependency-missing");
        return false;
    }
    const FReferenceSkeleton& reference = dependencies.Skeleton->GetReferenceSkeleton();
    if (reference.GetRawBoneNum() != decoded.BoneNames.Num())
    {
        error = TEXT("animation-skeleton-bone-count-mismatch");
        return false;
    }
    for (int32 index = 0; index < decoded.BoneNames.Num(); ++index)
    {
        if (reference.GetRawRefBoneInfo()[index].Name.ToString() != decoded.BoneNames[index])
        {
            error = TEXT("animation-skeleton-bone-name-mismatch");
            return false;
        }
    }
    return true;
}

bool SequenceMatches(const UAnimSequence& sequence, const USkeleton& skeleton,
                     const FTMXYAnimationImportSpec& spec, const int32 clipIndex)
{
    const FTMXYAnimationClipSpec& expected = spec.Clips[clipIndex];
    const IAnimationDataModel* model = sequence.GetDataModel();
    FMetaData& metadata = sequence.GetPackage()->GetMetaData();
    TArray<FName> names;
    if (model != nullptr)
    {
        model->GetBoneTrackNames(names);
    }
    if (sequence.GetSkeleton() != &skeleton || model == nullptr ||
        metadata.GetValue(&sequence, ManifestHashKey) != spec.ManifestSha256 ||
        metadata.GetValue(&sequence, ImporterVersionKey) != ImporterVersion ||
        metadata.GetValue(&sequence, SourceNameKey) != expected.SourceName ||
        metadata.GetValue(&sequence, SourceIndexKey) != FString::FromInt(expected.SourceIndex) ||
        metadata.GetValue(&sequence, LegacySelfLoopKey) !=
            (expected.bLegacySelfLoop ? TEXT("true") : TEXT("false")) ||
        metadata.GetValue(&sequence, RootMotionPolicyKey) != RootMotionPolicy ||
        model->GetNumberOfFrames() != expected.ExpectedFrameCount - 1 ||
        model->GetNumberOfKeys() != expected.ExpectedFrameCount ||
        model->GetNumBoneTracks() != expected.ExpectedTrackCount ||
        model->GetFrameRate() != FFrameRate(spec.SampleRateNumerator, spec.SampleRateDenominator) ||
        names.Num() != expected.ExpectedTrackCount)
    {
        return false;
    }
    return FMath::IsNearlyEqual(model->GetPlayLength(), expected.ExpectedSampledDurationSeconds,
                                0.000001);
}

bool SaveSequence(UAnimSequence& sequence, const FString& packageName)
{
    const FString filename = FPackageName::LongPackageNameToFilename(
        packageName, FPackageName::GetAssetPackageExtension());
    FSavePackageArgs args;
    args.TopLevelFlags = RF_Public | RF_Standalone;
    args.SaveFlags = SAVE_None;
    return UPackage::SavePackage(sequence.GetPackage(), &sequence, *filename, args);
}

UAnimSequence* BuildSequence(const FTMXYAnimationImportSpec& spec,
                             const FTMXYDecodedAnimSet& decoded, const int32 clipIndex,
                             USkeleton& skeleton, FString& error)
{
    const FTMXYAnimationClipSpec& clipSpec = spec.Clips[clipIndex];
    const FTMXYDecodedAnimClip& clip = decoded.Clips[clipIndex];
    const FString assetName = FPackageName::GetLongPackageAssetName(clipSpec.PackageName);
    UPackage* package = CreatePackage(*clipSpec.PackageName);
    UAnimSequence* sequence =
        NewObject<UAnimSequence>(package, *assetName, RF_Public | RF_Standalone);
    sequence->SetSkeleton(&skeleton);
    IAnimationDataController& controller = sequence->GetController();
    controller.InitializeModel();
    controller.OpenBracket(NSLOCTEXT("TMXYImporter", "ImportAnimation", "Import animation"), false);
    controller.SetFrameRate(FFrameRate(spec.SampleRateNumerator, spec.SampleRateDenominator),
                            false);
    controller.SetNumberOfFrames(FFrameNumber(clipSpec.ExpectedFrameCount - 1), false);
    TArray<FVector3f> scales;
    scales.Init(FVector3f::OneVector, clipSpec.ExpectedFrameCount);
    bool populated = true;
    for (int32 trackIndex = 0; trackIndex < decoded.BoneNames.Num(); ++trackIndex)
    {
        const FName boneName(*decoded.BoneNames[trackIndex]);
        populated = populated && controller.AddBoneCurve(boneName, false) &&
                    controller.SetBoneTrackKeys(boneName, clip.Tracks[trackIndex].PositionsCm,
                                                clip.Tracks[trackIndex].Rotations, scales, false);
    }
    controller.NotifyPopulated();
    controller.CloseBracket(false);
    if (!populated)
    {
        error = TEXT("animation-controller-population-failed");
        return nullptr;
    }
    package->GetMetaData().SetValue(sequence, ManifestHashKey, *spec.ManifestSha256);
    package->GetMetaData().SetValue(sequence, ImporterVersionKey, ImporterVersion);
    package->GetMetaData().SetValue(sequence, SourceNameKey, *clipSpec.SourceName);
    package->GetMetaData().SetValue(sequence, SourceIndexKey,
                                    *FString::FromInt(clipSpec.SourceIndex));
    package->GetMetaData().SetValue(sequence, LegacySelfLoopKey,
                                    clipSpec.bLegacySelfLoop ? TEXT("true") : TEXT("false"));
    package->GetMetaData().SetValue(sequence, RootMotionPolicyKey, RootMotionPolicy);
    sequence->PostEditChange();
    sequence->MarkPackageDirty();
    if (!SaveSequence(*sequence, clipSpec.PackageName))
    {
        error = TEXT("animation-package-save-failed");
        return nullptr;
    }
    return sequence;
}

bool ImportSequences(const FTMXYAnimationImportSpec& spec, const FTMXYDecodedAnimSet& decoded,
                     USkeleton& skeleton, FString& error)
{
    TArray<UAnimSequence*> existing;
    existing.SetNum(spec.Clips.Num());
    for (int32 index = 0; index < spec.Clips.Num(); ++index)
    {
        existing[index] =
            LoadObject<UAnimSequence>(nullptr, *ObjectPath(spec.Clips[index].PackageName));
        if (existing[index] != nullptr && !SequenceMatches(*existing[index], skeleton, spec, index))
        {
            error = TEXT("animation-existing-asset-mismatch");
            return false;
        }
    }
    for (int32 index = 0; index < spec.Clips.Num(); ++index)
    {
        if (existing[index] == nullptr &&
            BuildSequence(spec, decoded, index, skeleton, error) == nullptr)
        {
            return false;
        }
    }
    return true;
}

bool LoadAndValidate(const FTMXYAnimationImportSpec& spec, FTMXYDecodedAnimSet& decoded,
                     FString& error)
{
    FString text;
    TArray<uint8> buffer;
    if (!FFileHelper::LoadFileToString(text, *spec.GltfPath) ||
        !FFileHelper::LoadFileToArray(buffer, *spec.BufferPath) ||
        !DecodeTMXYAnimGltf(text, buffer, spec.BufferRelativePath, spec.ExpectedBoneCount,
                            spec.Clips.Num(), decoded, error))
    {
        if (error.IsEmpty())
        {
            error = TEXT("animation-payload-read-failed");
        }
        return false;
    }
    return ValidateDecoded(spec, decoded, error) && ValidateMetadata(spec, error);
}
} // namespace

FTMXYAnimationImporter::FTMXYAnimationImporter(FString rebuildRoot)
    : RebuildRoot(FPaths::ConvertRelativePathToFull(MoveTemp(rebuildRoot)))
{
    FPaths::NormalizeDirectoryName(RebuildRoot);
}

FName FTMXYAnimationImporter::GetFormatId() const
{
    return TEXT("khronos.gltf-json");
}

FTMXYImportItemResult FTMXYAnimationImporter::ImportArtifact(const FTMXYImportRequest& request,
                                                             const FString& artifactId)
{
    FTMXYAnimationImportSpec spec;
    FTMXYDecodedAnimSet decoded;
    FLoadedDependencies dependencies;
    FString error;
    const bool imported = ReadTMXYAnimationSpec(RebuildRoot, request, artifactId, spec, error) &&
                          LoadAndValidate(spec, decoded, error) &&
                          LoadDependencies(spec, decoded, dependencies, error) &&
                          ImportSequences(spec, decoded, *dependencies.Skeleton, error);
    if (!imported)
    {
        return MakeFailure(request, error);
    }
    FTMXYImportItemResult result;
    result.RequestId = request.RequestId;
    result.RelativeManifestPath = request.RelativeManifestPath;
    result.Status = TEXT("imported");
    result.ManifestSha256 = spec.ManifestSha256;
    result.OutputPackageName = spec.Clips[0].PackageName;
    result.ArtifactCount = spec.Clips.Num();
    result.ImportedAssetCount = spec.Clips.Num();
    result.bSucceeded = true;
    return result;
}

FTMXYReimportDecision
FTMXYAnimationImporter::EvaluateReimport(const FTMXYReimportRequest& request) const
{
    if (request.FormatId != GetFormatId() || !request.PackageName.StartsWith(AnimationRoot))
    {
        return {false, TEXT("animation-reimport-boundary-invalid")};
    }
    const FTMXYImportRequest importRequest{request.ArtifactId, request.RelativeManifestPath,
                                           ETMXYImportMode::SingleFixture};
    FTMXYAnimationImportSpec spec;
    FString error;
    if (!ReadTMXYAnimationSpec(RebuildRoot, importRequest, request.ArtifactId, spec, error))
    {
        return {false, error};
    }
    for (const FTMXYAnimationClipSpec& clip : spec.Clips)
    {
        if (clip.PackageName == request.PackageName)
        {
            return {true, TEXT("animation-reimport-supported")};
        }
    }
    return {false, TEXT("animation-reimport-target-mismatch")};
}

FTMXYImportItemResult FTMXYAnimationImporter::Reimport(const FTMXYReimportRequest& request)
{
    const FTMXYReimportDecision decision = EvaluateReimport(request);
    const FTMXYImportRequest importRequest{request.ArtifactId, request.RelativeManifestPath,
                                           ETMXYImportMode::SingleFixture};
    return decision.bCanReimport ? ImportArtifact(importRequest, request.ArtifactId)
                                 : MakeFailure(importRequest, decision.Reason);
}
