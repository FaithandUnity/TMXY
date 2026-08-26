#include "tmxy/package/package_normalized_tree.hpp"

#include <cstdint>
#include <iostream>
#include <string_view>

namespace
{

class TestContext final
{
  public:
    void expect(const bool condition, const std::string_view message)
    {
        if (!condition)
        {
            std::cerr << "FAILED: " << message << '\n';
            ++failure_count_;
        }
    }

    [[nodiscard]] int failure_count() const noexcept
    {
        return failure_count_;
    }

  private:
    int failure_count_{0};
};

void test_v1_normalization(TestContext& test)
{
    const tmxy::package::PackageV1Header header{
        .version = std::string(tmxy::package::kPackageV1Version),
        .records = {{.name_bytes = "n\x01", .class_name_bytes = "Class", .offset = 64, .size = 8}},
        .header_size = 64,
        .file_size = 72,
    };
    const auto tree = tmxy::package::normalize_package_tree(header, "Packages/sample");
    test.expect(tree.directory_offset == 0U && tree.directory_size == 64U,
                "Package 1.0 header normalizes as directory");
    const auto json = tmxy::package::package_tree_to_json(tree);
    test.expect(json.find(R"("schema":"tmxy.package.tree","schema_version":1)") !=
                    std::string::npos,
                "schema identity serialized");
    test.expect(json.find(R"("name":{"encoding":"opaque-bytes","hex":"6e01"})") !=
                    std::string::npos,
                "opaque name bytes serialized as hex");
    test.expect(json.find(R"("references":{"state":"unparsed","items":[]})") != std::string::npos,
                "references remain explicitly unparsed");
    test.expect(json.find(R"("preservation":"source-span")") != std::string::npos,
                "unknown body span preserved");
}

void test_modern_normalization(TestContext& test)
{
    const tmxy::package::PackageV2Header v2{
        .version = std::string(tmxy::package::kPackageV2Version),
        .records = {},
        .directory_offset = 29,
        .directory_size = 18,
        .header_size = 47,
        .file_size = 47,
    };
    const tmxy::package::PackageV3Header v3{
        .version = std::string(tmxy::package::kPackageV3Version),
        .records = {},
        .directory_offset = 29,
        .directory_size = 18,
        .header_size = 47,
        .file_size = 47,
    };
    const auto tree_v2 = tmxy::package::normalize_package_tree(v2, "v2");
    const auto tree_v3 = tmxy::package::normalize_package_tree(v3, "v3");
    test.expect(tree_v2.directory_offset == 29U && tree_v2.directory_size == 18U,
                "Package 2.0 directory preserved");
    test.expect(tree_v3.directory_offset == 29U && tree_v3.directory_size == 18U,
                "Package 3.0 directory preserved");
    test.expect(tmxy::package::package_tree_to_json(tree_v2).find("VER 2.0") != std::string::npos,
                "Package 2.0 version serialized");
    test.expect(tmxy::package::package_tree_to_json(tree_v3).find("VER 3.0") != std::string::npos,
                "Package 3.0 version serialized");
}

void test_json_escaping(TestContext& test)
{
    const tmxy::package::PackageV1Header header{
        .version = std::string(tmxy::package::kPackageV1Version),
        .records = {},
        .header_size = 29,
        .file_size = 29,
    };
    const auto json = tmxy::package::package_tree_to_json(
        tmxy::package::normalize_package_tree(header, "a\"b\\c\n"));
    test.expect(json.find(R"("label":"a\"b\\c\n")") != std::string::npos,
                "source label JSON escaping");
}

} // namespace

int main()
{
    TestContext test;
    test_v1_normalization(test);
    test_modern_normalization(test);
    test_json_escaping(test);
    return test.failure_count() == 0 ? 0 : 1;
}
