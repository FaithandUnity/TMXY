#if WITH_DEV_AUTOMATION_TESTS

#include "Dom/JsonObject.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "TMXYImporterService.h"

namespace
{
class FFakeAssetImporter final : public ITMXYAssetImporter
{
  public:
    FName GetFormatId() const override
    {
        return TEXT("tmxy.test.fixture");
    }

    FTMXYImportItemResult ImportArtifact(const FTMXYImportRequest& request,
                                         const FString& artifactId) override
    {
        FTMXYImportItemResult result;
        result.RequestId = request.RequestId;
        result.RelativeManifestPath = request.RelativeManifestPath;
        result.Status = TEXT("imported-test-fixture");
        result.ErrorCode = artifactId;
        result.bSucceeded = true;
        return result;
    }

    FTMXYReimportDecision EvaluateReimport(const FTMXYReimportRequest& request) const override
    {
        return {!request.ArtifactId.IsEmpty(), TEXT("test-fixture-supported")};
    }

    FTMXYImportItemResult Reimport(const FTMXYReimportRequest& request) override
    {
        FTMXYImportItemResult result;
        result.RequestId = request.ArtifactId;
        result.RelativeManifestPath = request.RelativeManifestPath;
        result.Status = TEXT("reimported-test-fixture");
        result.bSucceeded = true;
        return result;
    }
};
} // namespace

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FTMXYImporterManifestBatchTest, "TMXY.Importer.ManifestBatch",
                                 EAutomationTestFlags::EditorContext |
                                     EAutomationTestFlags::EngineFilter)

bool FTMXYImporterManifestBatchTest::RunTest(const FString& parameters)
{
    static_cast<void>(parameters);
    const FString rebuildRoot =
        FPaths::ConvertRelativePathToFull(FPaths::Combine(FPaths::ProjectDir(), TEXT("../..")));
    FTMXYImporterService service(rebuildRoot);

    TArray<FTMXYImportRequest> requests;
    requests.Add({TEXT("manifest-a"), TEXT("Contracts/examples/asset-interchange-v1.example.json"),
                  ETMXYImportMode::ValidateOnly});
    requests.Add({TEXT("manifest-b"), TEXT("Contracts/examples/asset-interchange-v1.example.json"),
                  ETMXYImportMode::ValidateOnly});
    const FTMXYImportBatchResult batch = service.ValidateBatch(requests);
    TestEqual(TEXT("Batch request count"), batch.Items.Num(), 2);
    TestEqual(TEXT("Batch validated count"), batch.SucceededCount, 2);
    TestEqual(TEXT("Batch failed count"), batch.FailedCount, 0);
    TestEqual(TEXT("Batch creates no assets"), batch.ImportedAssetCount, 0);
    TestTrue(TEXT("Manifest SHA-256 is populated"), batch.Items[0].ManifestSha256.Len() == 64);
    TestTrue(TEXT("Manifest has source inputs"), batch.Items[0].SourceCount > 0);
    TestTrue(TEXT("Manifest has artifacts"), batch.Items[0].ArtifactCount > 0);

    const FString reportPath = FPaths::Combine(FPaths::ProjectSavedDir(),
                                               TEXT("Automation/TMXYImporter/p1-21-report.json"));
    FString reportError;
    TestTrue(TEXT("Golden before/after report is written"),
             service.WriteGoldenReport(batch, requests[0].RelativeManifestPath, reportPath,
                                       reportError));
    FString reportText;
    TSharedPtr<FJsonObject> report;
    TestTrue(TEXT("Generated report is readable"),
             FFileHelper::LoadFileToString(reportText, *reportPath));
    const TSharedRef<TJsonReader<>> reader = TJsonReaderFactory<>::Create(reportText);
    TestTrue(TEXT("Generated report is valid JSON"),
             FJsonSerializer::Deserialize(reader, report) && report.IsValid());
    if (report.IsValid())
    {
        TestEqual(TEXT("Generated report schema"), report->GetStringField(TEXT("schema")),
                  FString(TEXT("tmxy.ue.golden-import-report")));
        TestEqual(TEXT("Generated report mode"), report->GetStringField(TEXT("import_mode")),
                  FString(TEXT("validate-only")));
        TestEqual(TEXT("Generated report status"),
                  report->GetObjectField(TEXT("outcome"))->GetStringField(TEXT("status")),
                  FString(TEXT("passed")));
    }

    const FTMXYReimportRequest unknownFormatRequest{
        TEXT("tmxy.unknown.fixture"), TEXT("/Game/TMXY/Golden/Test/Unknown"),
        requests[0].RelativeManifestPath, TEXT("fixture")};
    TestFalse(TEXT("Unknown format without a registered handler is rejected"),
              service.EvaluateReimport(unknownFormatRequest).bCanReimport);

    const TSharedRef<FFakeAssetImporter> fakeImporter = MakeShared<FFakeAssetImporter>();
    TestTrue(TEXT("Format importer registers once"), service.RegisterImporter(fakeImporter));
    TestFalse(TEXT("Duplicate format importer is rejected"),
              service.RegisterImporter(fakeImporter));
    FTMXYReimportRequest reimportRequest{TEXT("tmxy.test.fixture"),
                                         TEXT("/Game/TMXY/Golden/Test/Fixture"),
                                         requests[0].RelativeManifestPath, TEXT("fixture")};
    TestTrue(TEXT("Registered handler accepts bounded reimport"),
             service.EvaluateReimport(reimportRequest).bCanReimport);
    TestTrue(TEXT("Reimport dispatch succeeds"), service.Reimport(reimportRequest).bSucceeded);
    reimportRequest.PackageName = TEXT("/Game/Unsafe/Fixture");
    TestFalse(TEXT("Reimport outside golden root is rejected"),
              service.EvaluateReimport(reimportRequest).bCanReimport);
    return !HasAnyErrors();
}

#endif
