#pragma once

#include "TMXYImportTypes.h"

class TMXYIMPORTER_API ITMXYAssetImporter
{
  public:
    virtual ~ITMXYAssetImporter() = default;

    virtual FName GetFormatId() const = 0;
    virtual FTMXYImportItemResult ImportArtifact(const FTMXYImportRequest& request,
                                                 const FString& artifactId) = 0;
    virtual FTMXYReimportDecision EvaluateReimport(const FTMXYReimportRequest& request) const = 0;
    virtual FTMXYImportItemResult Reimport(const FTMXYReimportRequest& request) = 0;
};
