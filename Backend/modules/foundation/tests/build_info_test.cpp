#include "tmxy/foundation/build_info.hpp"

#include <cstdlib>

int main()
{
    const tmxy::foundation::BuildInfo& build_info = tmxy::foundation::current_build_info();
    if (build_info.product != "tmxy-backend")
    {
        return EXIT_FAILURE;
    }
    if (build_info.version_major != 0 || build_info.version_minor != 1 ||
        build_info.version_patch != 0)
    {
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
