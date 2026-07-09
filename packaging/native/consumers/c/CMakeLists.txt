cmake_minimum_required(VERSION 3.20)
project(SSHFlingCConsumer LANGUAGES C)

find_package(SSHFling CONFIG REQUIRED)

add_executable(sshfling-c-consumer main.c)
target_link_libraries(sshfling-c-consumer PRIVATE SSHFling::shared)
