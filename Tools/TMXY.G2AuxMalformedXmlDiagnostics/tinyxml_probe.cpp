#include "tinyxml.h"

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

namespace {

struct TreeShape {
    std::size_t nodes = 0;
    std::size_t elements = 0;
    std::size_t attributes = 0;
    std::size_t texts = 0;
    std::size_t comments = 0;
};

bool IsFamily(const std::string& value) {
    return value == "client" || value == "server";
}

bool IsLowerHexSha256(const std::string& value) {
    if (value.size() != 64) {
        return false;
    }
    return std::all_of(value.begin(), value.end(), [](unsigned char item) {
        return std::isdigit(item) != 0 || (item >= 'a' && item <= 'f');
    });
}

void CountNode(const TiXmlNode* node, TreeShape& shape) {
    if (!node) {
        return;
    }
    ++shape.nodes;
    switch (node->Type()) {
        case TiXmlNode::ELEMENT: {
            ++shape.elements;
            const TiXmlElement* element = node->ToElement();
            if (element) {
                for (const TiXmlAttribute* attribute = element->FirstAttribute();
                     attribute;
                     attribute = attribute->Next()) {
                    ++shape.attributes;
                }
            }
            break;
        }
        case TiXmlNode::TEXT:
            ++shape.texts;
            break;
        case TiXmlNode::COMMENT:
            ++shape.comments;
            break;
        case TiXmlNode::DOCUMENT:
        case TiXmlNode::UNKNOWN:
        case TiXmlNode::DECLARATION:
        case TiXmlNode::TYPECOUNT:
            break;
    }
    for (const TiXmlNode* child = node->FirstChild(); child;
         child = child->NextSibling()) {
        CountNode(child, shape);
    }
}

TreeShape CountDocument(const TiXmlDocument& document) {
    TreeShape shape;
    for (const TiXmlNode* child = document.FirstChild(); child;
         child = child->NextSibling()) {
        CountNode(child, shape);
    }
    return shape;
}

void PrintBool(bool value) {
    std::cout << (value ? "true" : "false");
}

void PrintNullableInt(bool present, std::int64_t value) {
    if (present) {
        std::cout << value;
    } else {
        std::cout << "null";
    }
}

void PrintRecord(const std::string& family,
                 int member,
                 const std::string& content_sha256,
                 const char* input_path) {
    TiXmlDocument loaded;
    const bool load_file_success =
        loaded.LoadFile(input_path, TIXML_ENCODING_UNKNOWN);
    const bool load_file_error = loaded.Error();
    const bool load_file_root = loaded.RootElement() != nullptr;

    std::ifstream stream(input_path, std::ios::binary);
    if (!stream) {
        return;
    }
    const std::vector<char> input((std::istreambuf_iterator<char>(stream)),
                                  std::istreambuf_iterator<char>());
    std::vector<char> probe_input(input);
    probe_input.push_back('\0');

    TiXmlDocument direct;
    const char* const returned = direct.Parse(
        probe_input.data(), nullptr, TIXML_ENCODING_UNKNOWN);
    const bool direct_error = direct.Error();
    const bool direct_root = direct.RootElement() != nullptr;
    const TreeShape shape = CountDocument(direct);

    const std::uintptr_t begin =
        reinterpret_cast<std::uintptr_t>(probe_input.data());
    const std::uintptr_t end = begin + input.size();
    const std::uintptr_t result = reinterpret_cast<std::uintptr_t>(returned);
    const bool returned_in_input = returned && result >= begin && result <= end;
    const std::size_t returned_offset =
        returned_in_input ? static_cast<std::size_t>(result - begin) : 0;
    const bool full_input_consumed =
        returned_in_input && returned_offset == input.size();
    const bool null_partial_tree =
        load_file_success && !load_file_error && load_file_root && !returned &&
        !direct_error && direct_root && shape.nodes > 0 && !full_input_consumed;

    std::cout << "{\"family\":\"" << family << "\",\"member\":" << member
              << ",\"content_sha256\":\"" << content_sha256 << "\""
              << ",\"input_read_success\":true"
              << ",\"load_file_success\":";
    PrintBool(load_file_success);
    std::cout << ",\"load_file_error_flag\":";
    PrintBool(load_file_error);
    std::cout << ",\"load_file_error_id\":" << loaded.ErrorId()
              << ",\"load_file_error_line\":";
    PrintNullableInt(load_file_error, loaded.ErrorRow());
    std::cout << ",\"load_file_error_column\":";
    PrintNullableInt(load_file_error, loaded.ErrorCol());
    std::cout << ",\"load_file_root_present\":";
    PrintBool(load_file_root);
    std::cout << ",\"direct_parse_returned_null\":";
    PrintBool(returned == nullptr);
    std::cout << ",\"direct_parse_returned_offset\":";
    PrintNullableInt(returned_in_input,
                     static_cast<std::int64_t>(returned_offset));
    std::cout << ",\"direct_parse_error_flag\":";
    PrintBool(direct_error);
    std::cout << ",\"direct_parse_error_id\":" << direct.ErrorId()
              << ",\"direct_parse_error_line\":";
    PrintNullableInt(direct_error, direct.ErrorRow());
    std::cout << ",\"direct_parse_error_column\":";
    PrintNullableInt(direct_error, direct.ErrorCol());
    std::cout << ",\"direct_parse_root_present\":";
    PrintBool(direct_root);
    std::cout << ",\"full_input_consumed\":";
    PrintBool(full_input_consumed);
    std::cout << ",\"direct_parse_null_partial_tree\":";
    PrintBool(null_partial_tree);
    std::cout << ",\"probe_input_nul_appended\":true"
              << ",\"nodes\":" << shape.nodes
              << ",\"elements\":" << shape.elements
              << ",\"attributes\":" << shape.attributes
              << ",\"texts\":" << shape.texts
              << ",\"comments\":" << shape.comments << "}\n";
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 4 || ((argc - 2) % 2) != 0 || !IsFamily(argv[1])) {
        return 64;
    }
    const std::string family(argv[1]);
    for (int argument = 2, member = 0; argument < argc;
         argument += 2, ++member) {
        const std::string content_sha256(argv[argument + 1]);
        if (!IsLowerHexSha256(content_sha256)) {
            return 65;
        }
        std::ifstream readable(argv[argument], std::ios::binary);
        if (!readable) {
            return 66;
        }
        readable.close();
        PrintRecord(family, member, content_sha256, argv[argument]);
    }
    return 0;
}
