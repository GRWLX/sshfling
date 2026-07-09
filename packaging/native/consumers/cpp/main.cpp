#include <sshfling/sshfling.hpp>

#include <iostream>

int main(int argc, char **argv) {
    if (argc != 2 || sshfling::version() != argv[1]) {
        std::cerr << "C++ library version mismatch: " << sshfling::version() << '\n';
        return 1;
    }
    return sshfling::run({"--version"});
}
