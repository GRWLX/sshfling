#ifndef SSHFLING_SSHFLING_HPP
#define SSHFLING_SSHFLING_HPP

#include <initializer_list>
#include <string>
#include <string_view>
#include <vector>

#include <sshfling/sshfling.h>

namespace sshfling {

inline std::string_view version() noexcept {
    return sshfling_version();
}

inline int run(const std::vector<std::string>& arguments) {
    std::vector<const char*> raw;
    raw.reserve(arguments.size());
    for (const auto& argument : arguments) {
        raw.push_back(argument.c_str());
    }
    return sshfling_run(raw.size(), raw.data());
}

inline int run(std::initializer_list<std::string> arguments) {
    return run(std::vector<std::string>(arguments));
}

}  // namespace sshfling

#endif
