#pragma once

#include "ITMXYAssetImporter.h"

class TMXYIMPORTER_API FTMXYImporterService final
{
  public:
    explicit FTMXYImporterService(FString rebuildRoot);

    bool RegisterImporter(const TSharedRef<ITMXYAssetImporter>& importer);
    int32 GetRegisteredImporterCount() const;
    FTMXYImportBatchResult ValidateBatch(const TArray<FTMXYImportRequest>& requests) const;
    FTMXYImportItemResult ImportArtifact(const FTMXYImportRequest& request,
                                         const FString& artifactId) const;
    FTMXYReimportDecision EvaluateReimport(const FTMXYReimportRequest& request) const;
    FTMXYImportItemResult Reimport(const FTMXYReimportRequest& request) const;
    bool WriteGoldenReport(const FTMXYImportBatchResult& batch, const FString& relativeManifestPath,
                           const FString& outputPath, FString& error) const;

  private:
    FTMXYImportItemResult ValidateManifest(const FTMXYImportRequest& request) const;
    bool ResolveArtifactFormat(const FTMXYImportRequest& request, const FString& artifactId,
                               FName& formatId, FString& error) const;
    bool ResolveRepositoryPath(const FString& relativePath, FString& resolvedPath) const;

    FString RebuildRoot;
    TMap<FName, TSharedRef<ITMXYAssetImporter>> Importers;
};
