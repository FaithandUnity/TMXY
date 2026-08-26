#pragma once

#include "ITMXYAssetImporter.h"

class TMXYIMPORTER_API FTMXYGltfImporter final : public ITMXYAssetImporter
{
  public:
    explicit FTMXYGltfImporter(FString rebuildRoot);

    FName GetFormatId() const override;
    FTMXYImportItemResult ImportArtifact(const FTMXYImportRequest& request,
                                         const FString& artifactId) override;
    FTMXYReimportDecision EvaluateReimport(const FTMXYReimportRequest& request) const override;
    FTMXYImportItemResult Reimport(const FTMXYReimportRequest& request) override;

  private:
    ITMXYAssetImporter* ResolveManifestImporter(const FString& relativeManifestPath,
                                                FString& error) const;
    ITMXYAssetImporter* ResolvePackageImporter(const FString& packageName) const;

    FString RebuildRoot;
    TSharedRef<ITMXYAssetImporter> StaticMeshImporter;
    TSharedRef<ITMXYAssetImporter> SkeletalMeshImporter;
    TSharedRef<ITMXYAssetImporter> AnimationImporter;
};
