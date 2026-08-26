#include "tmxy/animation/animation_export.hpp"

#include "tmxy/transform/legacy_to_ue_transform.hpp"

#include <algorithm>
#include <iomanip>
#include <limits>
#include <sstream>
#include <string>
#include <string_view>

namespace tmxy::animation
{
namespace
{

[[nodiscard]] std::string json_string(const std::string_view value)
{
    std::ostringstream output;
    output << '"';
    for (const char raw_character : value)
    {
        const auto character = static_cast<unsigned char>(raw_character);
        switch (character)
        {
        case '"':
            output << "\\\"";
            break;
        case '\\':
            output << "\\\\";
            break;
        case '\n':
            output << "\\n";
            break;
        case '\r':
            output << "\\r";
            break;
        case '\t':
            output << "\\t";
            break;
        default:
            if (character < 0x20U || character >= 0x80U)
            {
                output << "\\u00" << std::hex << std::setw(2) << std::setfill('0')
                       << static_cast<unsigned int>(character) << std::dec;
            }
            else
            {
                output << static_cast<char>(character);
            }
        }
    }
    output << '"';
    return output.str();
}

[[nodiscard]] std::string csv_string(const std::string_view value)
{
    std::string output{"\""};
    for (const char character : value)
    {
        if (character == '"')
        {
            output += "\"\"";
        }
        else
        {
            output.push_back(character);
        }
    }
    output.push_back('"');
    return output;
}

void write_vec3(std::ostringstream& output, const skeletal_mesh::Vec3& value)
{
    output << '[' << value.x << ", " << value.y << ", " << value.z << ']';
}

void write_notify_names(std::ostringstream& output, const AnimationDescriptor& descriptor)
{
    output << '[';
    for (std::size_t index = 0; index < descriptor.notify_object_names.size(); ++index)
    {
        if (index != 0U)
        {
            output << ", ";
        }
        output << json_string(descriptor.notify_object_names[index]);
    }
    output << ']';
}

void write_clip(std::ostringstream& output, const AnimationClip& clip, const std::size_t index)
{
    const auto& descriptor = clip.descriptor;
    const auto& root = clip.root_motion;
    output << "    {\n"
           << "      \"index\": " << index << ",\n"
           << "      \"object_name_bytes\": " << json_string(descriptor.object_name_bytes) << ",\n"
           << "      \"animation_name_bytes\": " << json_string(descriptor.animation_name_bytes)
           << ",\n"
           << "      \"skeleton_root_name_bytes\": "
           << json_string(descriptor.skeleton_root_name_bytes) << ",\n"
           << "      \"frame_count\": " << descriptor.frame_count << ",\n"
           << "      \"frame_delta_seconds\": " << descriptor.frame_delta_seconds << ",\n"
           << "      \"sampled_duration_seconds\": " << clip.sampled_duration_seconds << ",\n"
           << "      \"legacy_loop_period_seconds\": " << clip.legacy_loop_period_seconds << ",\n"
           << "      \"self_loop\": " << (descriptor.self_loop ? "true" : "false") << ",\n"
           << "      \"track_count\": " << clip.track_count << ",\n"
           << "      \"key_count\": "
           << static_cast<std::uint64_t>(clip.track_count) *
                  static_cast<std::uint64_t>(descriptor.frame_count)
           << ",\n"
           << "      \"dense_prefix_track_ids\": true,\n"
           << "      \"notify_object_names\": ";
    write_notify_names(output, descriptor);
    output << ",\n"
           << "      \"unknown_property_count\": " << descriptor.unknown_properties.size() << ",\n"
           << "      \"root_motion\": {\n"
           << "        \"has_root_track\": " << (root.has_root_track ? "true" : "false") << ",\n"
           << "        \"classified_moving\": " << (root.classified_moving ? "true" : "false")
           << ",\n"
           << "        \"translation_delta_legacy_meters\": ";
    write_vec3(output, root.translation_delta_legacy_meters);
    output << ",\n        \"translation_delta_ue_centimeters\": ";
    write_vec3(output, root.translation_delta_ue_centimeters);
    output << ",\n"
           << "        \"translation_distance_legacy_meters\": "
           << root.translation_distance_legacy_meters << ",\n"
           << "        \"maximum_excursion_legacy_meters\": "
           << root.maximum_excursion_legacy_meters << ",\n"
           << "        \"angular_delta_degrees\": " << root.angular_delta_degrees << "\n"
           << "      }\n"
           << "    }";
}

} // namespace

std::string build_animation_json(const AnimationBinding& binding)
{
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<double>::max_digits10);
    const auto& payload = binding.payload;
    const auto moving_count =
        std::count_if(payload.clips.begin(), payload.clips.end(),
                      [](const AnimationClip& clip) { return clip.root_motion.classified_moving; });
    output << "{\n"
           << "  \"schema_version\": 1,\n"
           << "  \"source_contract\": \"QSkelAnim Package metadata plus headerless dense-prefix "
              ".anim tracks\",\n"
           << "  \"skeletal_mesh_object_name_bytes\": "
           << json_string(binding.package.skeletal_mesh.object_name_bytes) << ",\n"
           << "  \"skeleton_bone_count\": " << binding.package.skeletal_mesh.descriptor.bones.size()
           << ",\n"
           << "  \"animation_count\": " << payload.clips.size() << ",\n"
           << "  \"total_track_count\": " << payload.total_track_count << ",\n"
           << "  \"total_key_count\": " << payload.total_key_count << ",\n"
           << "  \"root_moving_animation_count\": " << moving_count << ",\n"
           << "  \"emitter_point_count\": " << payload.emitter_points.size() << ",\n"
           << "  \"coordinate_contract\": {\n"
           << "    \"keys\": \"legacy local-space components, meters\",\n"
           << "    \"root_translation_delta_ue\": \"X-forward/Y-right/Z-up centimeters\",\n"
           << "    \"root_motion_policy\": \"measured root bone track; not extracted or removed\"\n"
           << "  },\n"
           << "  \"animations\": [\n";
    for (std::size_t index = 0; index < payload.clips.size(); ++index)
    {
        write_clip(output, payload.clips[index], index);
        output << (index + 1U == payload.clips.size() ? "\n" : ",\n");
    }
    output << "  ]\n}\n";
    return output.str();
}

std::string build_root_motion_csv(const AnimationBinding& binding)
{
    std::ostringstream output;
    output << std::setprecision(std::numeric_limits<double>::max_digits10)
           << "clip_index,animation_name,frame,time_seconds,legacy_x_m,legacy_y_m,legacy_z_m,"
              "ue_x_cm,ue_y_cm,ue_z_cm,quat_x,quat_y,quat_z,quat_w\n";
    for (std::size_t clip_index = 0; clip_index < binding.payload.clips.size(); ++clip_index)
    {
        const auto& clip = binding.payload.clips[clip_index];
        if (clip.tracks.empty())
        {
            continue;
        }
        const auto& keys = clip.tracks.front().keys;
        for (std::size_t frame = 0; frame < keys.size(); ++frame)
        {
            const auto& key = keys[frame];
            const auto ue = transform::LegacyToUETransform::position(
                {.x = key.translation.x, .y = key.translation.y, .z = key.translation.z});
            output << clip_index << ',' << csv_string(clip.descriptor.animation_name_bytes) << ','
                   << frame << ','
                   << static_cast<double>(frame) * clip.descriptor.frame_delta_seconds << ','
                   << key.translation.x << ',' << key.translation.y << ',' << key.translation.z
                   << ',';
            if (ue.has_value())
            {
                output << ue.value().x << ',' << ue.value().y << ',' << ue.value().z;
            }
            else
            {
                output << "0,0,0";
            }
            output << ',' << key.rotation.x << ',' << key.rotation.y << ',' << key.rotation.z << ','
                   << key.rotation.w << '\n';
        }
    }
    return output.str();
}

} // namespace tmxy::animation
