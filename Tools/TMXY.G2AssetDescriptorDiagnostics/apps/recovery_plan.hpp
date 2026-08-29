#pragma once

#include <cstddef>
#include <map>
#include <string>
#include <string_view>
#include <utility>

namespace tmxy::g2_asset_descriptor_diagnostics
{

struct RecoveryDirective final
{
    std::string asset_id;
    std::string candidate_id;
    std::string body_sha256;
    std::string source_sha256;
    std::string family;
    std::string recovery_kind;
    std::string strict_error_code;
    bool visited{false};
};

class RecoveryPlan final
{
  public:
    [[nodiscard]] static RecoveryPlan read(const std::string& path);

    [[nodiscard]] RecoveryDirective* find(std::string_view asset_id, std::string_view candidate_id);
    void require_complete() const;
    [[nodiscard]] std::size_t size() const noexcept;

  private:
    using Key = std::pair<std::string, std::string>;
    std::map<Key, RecoveryDirective> directives_;
};

} // namespace tmxy::g2_asset_descriptor_diagnostics
