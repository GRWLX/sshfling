cmake_minimum_required(VERSION 3.20)

set(SSHFLING_VERSION "0.0.0" CACHE STRING "SSHFling package version")
project(SSHFling VERSION "${SSHFLING_VERSION}" LANGUAGES C CXX)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(SSHFLING_INSTALL_RUNTIME_DIR "${CMAKE_INSTALL_FULL_DATADIR}/sshfling")

add_library(sshfling_objects OBJECT src/sshfling.c)
set_target_properties(sshfling_objects PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(sshfling_objects PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_compile_definitions(
    sshfling_objects
    PRIVATE
        SSHFLING_VERSION="${PROJECT_VERSION}"
        SSHFLING_INSTALL_RUNTIME_DIR="${SSHFLING_INSTALL_RUNTIME_DIR}"
)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(sshfling_objects PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_library(sshfling_shared SHARED $<TARGET_OBJECTS:sshfling_objects>)
add_library(SSHFling::shared ALIAS sshfling_shared)
set_target_properties(
    sshfling_shared
    PROPERTIES
        OUTPUT_NAME sshfling
        VERSION "${PROJECT_VERSION}"
        SOVERSION "${PROJECT_VERSION_MAJOR}"
        EXPORT_NAME shared
)
target_include_directories(
    sshfling_shared
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)

add_library(sshfling_static STATIC $<TARGET_OBJECTS:sshfling_objects>)
add_library(SSHFling::static ALIAS sshfling_static)
set_target_properties(sshfling_static PROPERTIES OUTPUT_NAME sshfling EXPORT_NAME static)
target_include_directories(
    sshfling_static
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)

add_executable(sshfling-c src/main.c)
target_link_libraries(sshfling-c PRIVATE sshfling_shared)
set_target_properties(
    sshfling-c
    PROPERTIES
        INSTALL_RPATH "$ORIGIN/../${CMAKE_INSTALL_LIBDIR}"
)

enable_testing()
add_executable(sshfling-c-api-test consumers/c/main.c)
target_link_libraries(sshfling-c-api-test PRIVATE sshfling_shared)
add_test(NAME c-library-api COMMAND sshfling-c-api-test "${PROJECT_VERSION}")

add_executable(sshfling-cpp-api-test consumers/cpp/main.cpp)
target_link_libraries(sshfling-cpp-api-test PRIVATE sshfling_static)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(sshfling-cpp-api-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()
add_test(NAME cpp-library-api COMMAND sshfling-cpp-api-test "${PROJECT_VERSION}")

set_tests_properties(
    c-library-api cpp-library-api
    PROPERTIES
        ENVIRONMENT "SSHFLING_C_RUNTIME_DIR=${CMAKE_CURRENT_SOURCE_DIR}/runtime"
        PASS_REGULAR_EXPRESSION "sshfling ${PROJECT_VERSION}"
)

configure_package_config_file(
    cmake/SSHFlingConfig.cmake.in
    "${CMAKE_CURRENT_BINARY_DIR}/SSHFlingConfig.cmake"
    INSTALL_DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/SSHFling"
)
write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/SSHFlingConfigVersion.cmake"
    VERSION "${PROJECT_VERSION}"
    COMPATIBILITY SameMajorVersion
)
configure_file(cmake/sshfling.pc.in "${CMAKE_CURRENT_BINARY_DIR}/sshfling.pc" @ONLY)

install(
    TARGETS sshfling_shared sshfling_static sshfling-c
    EXPORT SSHFlingTargets
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
install(
    EXPORT SSHFlingTargets
    FILE SSHFlingTargets.cmake
    NAMESPACE SSHFling::
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/SSHFling"
)
install(
    FILES
        "${CMAKE_CURRENT_BINARY_DIR}/SSHFlingConfig.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/SSHFlingConfigVersion.cmake"
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/SSHFling"
)
install(
    FILES "${CMAKE_CURRENT_BINARY_DIR}/sshfling.pc"
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig"
)
