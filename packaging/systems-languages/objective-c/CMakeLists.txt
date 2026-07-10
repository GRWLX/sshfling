cmake_minimum_required(VERSION 3.20)
project(SSHFlingObjectiveC VERSION 0.0.0 LANGUAGES C OBJC)

include(GNUInstallDirs)

set(SSHFLING_COMMON_DIR "${CMAKE_CURRENT_LIST_DIR}/common" CACHE PATH "Shared launcher source directory")

add_library(sshfling-objective-c
    src/SSHFling.m
    "${SSHFLING_COMMON_DIR}/sshfling_launcher.c"
)
target_include_directories(sshfling-objective-c
    PUBLIC "${CMAKE_CURRENT_LIST_DIR}/include"
    PRIVATE "${SSHFLING_COMMON_DIR}"
)
target_compile_definitions(sshfling-objective-c PRIVATE SSHFLING_VERSION="${PROJECT_VERSION}")
target_compile_definitions(
    sshfling-objective-c
    PRIVATE SSHFLING_INSTALL_RUNTIME_DIR="${CMAKE_INSTALL_FULL_DATADIR}/sshfling"
)
target_link_libraries(sshfling-objective-c PUBLIC objc)
set_target_properties(sshfling-objective-c PROPERTIES OUTPUT_NAME sshfling_objective_c)

add_executable(sshfling-objective-c-cli src/main.m)
target_link_libraries(sshfling-objective-c-cli PRIVATE sshfling-objective-c)
set_target_properties(
    sshfling-objective-c-cli
    PROPERTIES
        OUTPUT_NAME sshfling-objective-c
        INSTALL_RPATH "$ORIGIN/../${CMAKE_INSTALL_LIBDIR}"
)

install(
    TARGETS sshfling-objective-c sshfling-objective-c-cli
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
    LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
)
install(DIRECTORY include/ DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}")
install(PROGRAMS runtime/sshfling.py DESTINATION "${CMAKE_INSTALL_DATADIR}/sshfling")
install(
    DIRECTORY runtime/templates/
    DESTINATION "${CMAKE_INSTALL_DATADIR}/sshfling/templates"
    USE_SOURCE_PERMISSIONS
)
