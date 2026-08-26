#include "tmxy/animation/anim_reader.hpp"
#include "tmxy/animation/animation_export.hpp"
#include "tmxy/animation/package_animation_reader.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace
{

[[nodiscard]] std::vector<std::byte> read_file(const std::filesystem::path& path)
{
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream)
    {
        return {};
    }
    const auto end = stream.tellg();
    if (end <= 0 || end > std::numeric_limits<std::streamsize>::max())
    {
        return {};
    }
    std::vector<std::byte> bytes(static_cast<std::size_t>(end));
    stream.seekg(0);
    stream.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    return stream ? bytes : std::vector<std::byte>{};
}

[[nodiscard]] std::uint64_t fingerprint(const std::string_view text) noexcept
{
    std::uint64_t hash = 14695981039346656037ULL;
    for (const char character : text)
    {
        hash ^= static_cast<unsigned char>(character);
        hash *= 1099511628211ULL;
    }
    return hash;
}

struct Expectation final
{
    std::string_view object_name;
    std::string_view file_name;
    std::size_t clips{0};
    std::uint64_t keys{0};
    std::int32_t minimum_frames{0};
    std::int32_t maximum_frames{0};
    std::uint32_t minimum_tracks{0};
    std::uint32_t maximum_tracks{0};
    std::uint64_t tracks{0};
    std::size_t moving{0};
    std::size_t notify_references{0};
    std::uint64_t json_fingerprint{0};
    std::uint64_t csv_fingerprint{0};
    std::string_view first_object;
    std::string_view last_object;
};

[[nodiscard]] bool test_bound_sample(const std::vector<std::byte>& package_bytes,
                                     const std::filesystem::path& resource_root,
                                     const Expectation& expected)
{
    const auto animation_bytes = read_file(resource_root / "skchar" / expected.file_name);
    auto binding =
        tmxy::animation::bind_animation_set(package_bytes, expected.object_name, animation_bytes);
    if (!binding.has_value())
    {
        std::cerr << "bind-failed object=" << expected.object_name
                  << " code=" << tmxy::animation::to_string(binding.error().code)
                  << " offset=" << binding.error().absolute_offset
                  << " context=" << binding.error().context << '\n';
        return false;
    }
    const auto& payload = binding.value().payload;
    if (payload.clips.empty())
    {
        return false;
    }
    auto minimum_frames = std::numeric_limits<std::int32_t>::max();
    std::int32_t maximum_frames = 0;
    auto minimum_tracks = std::numeric_limits<std::uint32_t>::max();
    std::uint32_t maximum_tracks = 0;
    std::size_t moving = 0;
    std::size_t loops = 0;
    std::size_t notify_references = 0;
    double maximum_root_excursion = 0.0;
    for (const auto& clip : payload.clips)
    {
        minimum_frames = std::min(minimum_frames, clip.descriptor.frame_count);
        maximum_frames = std::max(maximum_frames, clip.descriptor.frame_count);
        minimum_tracks = std::min(minimum_tracks, clip.track_count);
        maximum_tracks = std::max(maximum_tracks, clip.track_count);
        moving += clip.root_motion.classified_moving ? 1U : 0U;
        loops += clip.descriptor.self_loop ? 1U : 0U;
        notify_references += clip.descriptor.notify_object_names.size();
        maximum_root_excursion =
            std::max(maximum_root_excursion, clip.root_motion.maximum_excursion_legacy_meters);
    }
    const auto json_first = tmxy::animation::build_animation_json(binding.value());
    const auto json_second = tmxy::animation::build_animation_json(binding.value());
    const auto csv_first = tmxy::animation::build_root_motion_csv(binding.value());
    const auto csv_second = tmxy::animation::build_root_motion_csv(binding.value());
    const auto metadata_consistent = std::ranges::all_of(
        payload.clips,
        [](const tmxy::animation::AnimationClip& clip)
        {
            return clip.descriptor.frame_delta_seconds == 0.033333335F &&
                   clip.descriptor.skeleton_root_name_bytes == "Bip01" &&
                   clip.tracks.size() == clip.track_count &&
                   std::ranges::all_of(clip.tracks,
                                       [&clip](const tmxy::animation::AnimationTrack& track)
                                       {
                                           return track.keys.size() ==
                                                  static_cast<std::size_t>(
                                                      clip.descriptor.frame_count);
                                       });
        });
    const auto json_hash = fingerprint(json_first);
    const auto csv_hash = fingerprint(csv_first);
    const bool passed =
        payload.clips.size() == expected.clips && payload.total_key_count == expected.keys &&
        payload.total_track_count == expected.tracks && minimum_frames == expected.minimum_frames &&
        maximum_frames == expected.maximum_frames && minimum_tracks == expected.minimum_tracks &&
        maximum_tracks == expected.maximum_tracks && payload.emitter_points.empty() &&
        loops == 0U && moving == expected.moving &&
        notify_references == expected.notify_references && metadata_consistent &&
        payload.clips.front().descriptor.object_name_bytes == expected.first_object &&
        payload.clips.back().descriptor.object_name_bytes == expected.last_object &&
        json_first == json_second && csv_first == csv_second &&
        json_hash == expected.json_fingerprint && csv_hash == expected.csv_fingerprint;
    std::cout << "BOUND_ANIM result=" << (passed ? "PASS" : "FAIL")
              << " object=" << expected.object_name << " clips=" << payload.clips.size()
              << " tracks=" << payload.total_track_count << " keys=" << payload.total_key_count
              << " frames_min=" << minimum_frames << " frames_max=" << maximum_frames
              << " tracks_min=" << minimum_tracks << " tracks_max=" << maximum_tracks
              << " loops=" << loops << " moving=" << moving << " notify_refs=" << notify_references
              << " max_root_excursion_m=" << maximum_root_excursion
              << " emitters=" << payload.emitter_points.size() << " json_fnv=" << json_hash
              << " csv_fnv=" << csv_hash << '\n';
    return passed;
}

} // namespace

int main(const int argument_count, const char* const arguments[])
{
    if (argument_count != 3)
    {
        std::cerr
            << "usage: tmxy_anim_real_samples_test <packages-root> <skelmesh-resource-root>\n";
        return 2;
    }
    const std::filesystem::path packages_root(arguments[1]);
    const std::filesystem::path resource_root(arguments[2]);
    const auto package_bytes = read_file(packages_root / "SkelMesh" / "skchar");
    if (package_bytes.empty())
    {
        std::cerr << "package-read-failed\n";
        return 3;
    }
    const auto minimum_bytes = read_file(resource_root / "particle" / "ZFH_B_S_XALGF001.anim");
    const std::vector<tmxy::animation::AnimationDescriptor> empty_descriptors;
    const auto minimum = tmxy::animation::AnimReader::parse(minimum_bytes, empty_descriptors, 0U);
    const bool minimum_passed = minimum.has_value() && minimum.value().clips.empty() &&
                                minimum.value().emitter_points.empty();
    std::cout << "MINIMUM_ANIM result=" << (minimum_passed ? "PASS" : "FAIL")
              << " bytes=" << minimum_bytes.size() << " clips=0\n";

    const bool boy = test_bound_sample(package_bytes, resource_root,
                                       {.object_name = "skchar.Boy01",
                                        .file_name = "Boy01.anim",
                                        .clips = 272,
                                        .keys = 1'173'344,
                                        .minimum_frames = 12,
                                        .maximum_frames = 250,
                                        .minimum_tracks = 22,
                                        .maximum_tracks = 80,
                                        .tracks = 21'702,
                                        .moving = 261,
                                        .notify_references = 80,
                                        .json_fingerprint = 5'953'296'718'757'516'148ULL,
                                        .csv_fingerprint = 14'896'642'631'070'048'600ULL,
                                        .first_object = "skchar.Boy01_Action",
                                        .last_object = "skchar.Boy01_XL_zhaojia"});
    const bool girl = test_bound_sample(package_bytes, resource_root,
                                        {.object_name = "skchar.Girl01",
                                         .file_name = "Girl01.anim",
                                         .clips = 270,
                                         .keys = 1'188'320,
                                         .minimum_frames = 11,
                                         .maximum_frames = 341,
                                         .minimum_tracks = 80,
                                         .maximum_tracks = 80,
                                         .tracks = 21'600,
                                         .moving = 254,
                                         .notify_references = 80,
                                         .json_fingerprint = 10'011'155'713'230'011'151ULL,
                                         .csv_fingerprint = 12'537'756'524'220'434'413ULL,
                                         .first_object = "skchar.Girl01_Action",
                                         .last_object = "skchar.Girl01_XL_zhaojia"});
    return minimum_passed && boy && girl ? 0 : 1;
}
