cmake_minimum_required(VERSION 3.20)
project(SSHFlingCppConsumer LANGUAGES CXX)

find_package(SSHFling CONFIG REQUIRED)

add_executable(sshfling-cpp-consumer main.cpp)
target_link_libraries(sshfling-cpp-consumer PRIVATE SSHFling::static)
