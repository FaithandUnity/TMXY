#include <cstdint>
#include <tmxy/contracts/data/core_data_types.generated.hpp>

int main()
{
    using namespace tmxy::contracts::data;
    static_assert(model_count == 12U);

    ItemTableId item_id{};
    item_id.C0001 = std::uint64_t{1};
    ItemTableRecord item{};
    item.Id = item_id;

    SkillTableId skill_id{};
    skill_id.C0001 = std::uint64_t{2};
    skill_id.C0004 = std::uint64_t{3};

    UnitClsId unit_class_id{};
    return item.Id == item_id && skill_id.C0004 == std::uint64_t{3} && unit_class_id.C0001.empty()
               ? 0
               : 1;
}
