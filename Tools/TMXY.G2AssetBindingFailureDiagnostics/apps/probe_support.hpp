#pragma once

#include <cstddef>
#include <cstdint>
#include <exception>
#include <filesystem>
#include <map>
#include <span>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace tmxy::g2_asset_binding_failure
{

struct AssetEntry final
{
    std::string id;
    std::string relative_path;
    std::string source_sha256;
    std::uint64_t bytes{0};
    std::string family;
    std::string structure;
    std::string candidate_set_sha256;
    std::vector<std::string> candidate_ids;
};

struct CandidateInput final
{
    std::string id;
    std::string package_path;
    std::uint64_t body_offset{0};
    std::uint64_t body_size{0};
    std::string class_name;
};

struct PackageData final
{
    std::string relative_path;
    std::vector<std::byte> bytes;
};

struct Candidate final
{
    std::string id;
    std::string package_path;
    std::string object_name;
    std::uint64_t body_offset{0};
    std::uint64_t body_size{0};
    std::string class_name;
};

struct CandidateIndex final
{
    std::map<std::string, PackageData> packages;
    std::unordered_map<std::string, Candidate> candidates;
};

class ProbeFailure final : public std::exception
{
  public:
    explicit ProbeFailure(std::string category);
    [[nodiscard]] const char* what() const noexcept override;

  private:
    std::string category_;
};

[[noreturn]] void fail(std::string_view category);
[[nodiscard]] bool is_lower_hex_sha256(std::string_view value) noexcept;
[[nodiscard]] std::string lower_ascii(std::string value);
[[nodiscard]] std::filesystem::path safe_join(const std::filesystem::path& root,
                                              std::string_view relative);
[[nodiscard]] std::vector<std::byte> read_file(const std::filesystem::path& path);
[[nodiscard]] std::vector<AssetEntry> read_asset_tsv(const std::filesystem::path& path);
[[nodiscard]] std::vector<CandidateInput> read_candidate_tsv(const std::filesystem::path& path);
[[nodiscard]] CandidateIndex load_candidates(const std::filesystem::path& client_root,
                                             const std::vector<CandidateInput>& expected);
[[nodiscard]] std::span<const std::byte> candidate_body(const CandidateIndex& index,
                                                        const Candidate& candidate);
[[nodiscard]] std::string candidate_set_sha256(const std::vector<std::string>& ids);

} // namespace tmxy::g2_asset_binding_failure
