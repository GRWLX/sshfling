cmake_minimum_required(VERSION 3.20)
project(SSHFlingCStaticConsumer LANGUAGES C)

find_package(SSHFling CONFIG REQUIRED)

add_executable(sshfling-c-static-consumer ../c/main.c)
target_link_libraries(sshfling-c-static-consumer PRIVATE SSHFling::static)
