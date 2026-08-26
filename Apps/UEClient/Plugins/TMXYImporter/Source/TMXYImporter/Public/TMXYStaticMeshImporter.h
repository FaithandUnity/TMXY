#pragma once

#include "ITMXYAssetImporter.h"

class TMXYIMPORTER_API FTMXYStaticMeshImporter final : public ITMXYAssetImporter
{
  public:
    explicit FTMXYStaticMeshImporter(FString rebuildRoot);

    FName GetFormatId() const override;
    FTMXYImportItemResult ImportArtifact(const FTMXYImportRequest& request,
                                         const FString& artifactId) override;
    FTMXYReimportDecision EvaluateReimport(const FTMXYReimportRequest& request) const override;
    FTMXYImportItemResult Reimport(const FTMXYReimportRequest& request) override;

  private:
    FString RebuildRoot;
};
