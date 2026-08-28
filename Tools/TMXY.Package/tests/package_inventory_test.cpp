#include "tmxy/package/package_inventory.hpp"
#include "tmxy/package/package_v1.hpp"

#include <cstddef>
#include <iostream>
#include <string_view>
#include <vector>

namespace
{

struct TestContext final
{
    int failures{0};

    void expect(const bool condition, const std::string_view message)
    {
        if (!condition)
        {
            std::cerr << message << '\n';
            ++failures;
        }
    }
};

[[nodiscard]] std::vector<std::byte> truncated_v1()
{
    const auto version = tmxy::package::kPackageV1Version;
    std::vector<std::byte> bytes;
    bytes.reserve(2U + version.size());
    bytes.push_back(static_cast<std::byte>(version.size() & 0xFFU));
    bytes.push_back(static_cast<std::byte>((version.size() >> 8U) & 0xFFU));
    for (const char value : version)
    {
        bytes.push_back(static_cast<std::byte>(static_cast<unsigned char>(value)));
    }
    return bytes;
}

} // namespace

int main()
{
    TestContext test;
    const auto empty = tmxy::package::inspect_package({});
    test.expect(empty.version == "empty", "empty version classification");
    test.expect(!empty.recognized && !empty.parsed, "empty file is not parsed");
    test.expect(empty.error == "empty_file", "empty error classification");

    const std::vector unknown{std::byte{0x01}, std::byte{0x02}, std::byte{0x03}};
    const auto unknown_result = tmxy::package::inspect_package(unknown);
    test.expect(unknown_result.version == "unknown", "unknown version classification");
    test.expect(unknown_result.error == "unknown_version", "unknown error classification");

    const auto truncated = tmxy::package::inspect_package(truncated_v1());
    test.expect(truncated.version == "1.0" && truncated.recognized, "recognized truncated v1");
    test.expect(!truncated.parsed && truncated.error != "none", "truncated v1 fails closed");
    const auto json = tmxy::package::package_inventory_to_json(truncated);
    test.expect(json.find("\"unknown_object_count\":0") != std::string::npos,
                "inventory JSON exposes bounded unknown count");
    test.expect(json.find(R"("error":")") != std::string::npos,
                "inventory JSON exposes stable error class");
    return test.failures == 0 ? 0 : 1;
}
