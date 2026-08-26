#include "tmxy/foundation/build_info.hpp"

#include <cstdlib>
#include <iostream>

int main()
{
    try
    {
        const tmxy::foundation::BuildInfo& build_info = tmxy::foundation::current_build_info();
        std::cout << R"({"event":"service_starting","service":"tmxy-gateway","version":")"
                  << build_info.version_major << '.' << build_info.version_minor << '.'
                  << build_info.version_patch << "\"}\n";
        return EXIT_SUCCESS;
    }
    catch (...)
    {
        return EXIT_FAILURE;
    }
}
