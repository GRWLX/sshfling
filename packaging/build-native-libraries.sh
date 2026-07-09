#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

for tool in cmake make ninja gcc g++ pkg-config tar gzip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required to build the SSHFling C/C++ package." >&2
    exit 127
  fi
done

dist_dir="$repo_root/dist"
build_root="$repo_root/build/native-libraries"
project_name="sshfling-native-$version"
project_dir="$build_root/$project_name"
cmake_build="$build_root/cmake-build"
debug_build="$build_root/debug-build"
sanitizer_build="$build_root/sanitizer-build"
install_prefix="$build_root/install"
validation_dir="$build_root/validation"
archive_path="$dist_dir/$project_name.tar.gz"

export LC_ALL=C
export TZ=UTC
umask 022

source_date_epoch="${SOURCE_DATE_EPOCH:-}"
if [[ -z "$source_date_epoch" ]]; then
  source_date_epoch="$(git -C "$repo_root" log -1 --format=%ct HEAD 2>/dev/null || printf '1700000000')"
fi
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  echo "SOURCE_DATE_EPOCH must be an integer Unix timestamp." >&2
  exit 2
fi

copy_project() {
  rm -rf "$project_dir"
  install -d "$project_dir"
  cp -R "$repo_root/packaging/native/." "$project_dir/"
  install -m 0644 "$repo_root/LICENSE" "$project_dir/LICENSE"
  install -m 0644 "$repo_root/README.md" "$project_dir/README.md"
  install -d "$project_dir/runtime"
  install -m 0755 "$repo_root/bin/sshfling" "$project_dir/runtime/sshfling.py"

  # shellcheck source=packaging/copy-templates.sh
  source "$repo_root/packaging/copy-templates.sh"
  copy_sshfling_templates "$repo_root" "$project_dir/runtime/templates"

  sed -i "s/set(SSHFLING_VERSION \"0.0.0\"/set(SSHFLING_VERSION \"$version\"/" "$project_dir/CMakeLists.txt"
  grep -Fqx "set(SSHFLING_VERSION \"$version\" CACHE STRING \"SSHFling package version\")" "$project_dir/CMakeLists.txt"
}

build_and_install() {
  cmake \
    -S "$project_dir" \
    -B "$cmake_build" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_prefix" \
    -DCMAKE_INSTALL_LIBDIR=lib
  cmake --build "$cmake_build" --parallel
  SSHFLING_C_RUNTIME_DIR="$project_dir/runtime" \
    ctest --test-dir "$cmake_build" --output-on-failure
  cmake --install "$cmake_build"

  cmake \
    -S "$project_dir" \
    -B "$debug_build" \
    -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Debug
  cmake --build "$debug_build" --parallel
  SSHFLING_C_RUNTIME_DIR="$project_dir/runtime" \
    ctest --test-dir "$debug_build" --output-on-failure

  cmake \
    -S "$project_dir" \
    -B "$sanitizer_build" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
    -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
    -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined" \
    -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address,undefined"
  cmake --build "$sanitizer_build" --parallel
  SSHFLING_C_RUNTIME_DIR="$project_dir/runtime" \
    ASAN_OPTIONS="detect_leaks=1:halt_on_error=1" \
    UBSAN_OPTIONS="halt_on_error=1" \
    ctest --test-dir "$sanitizer_build" --output-on-failure
}

validate_install() {
  local smoke_project="$validation_dir/smoke-project"
  local c_build="$validation_dir/c-consumer"
  local c_static_build="$validation_dir/c-static-consumer"
  local cpp_build="$validation_dir/cpp-consumer"
  local pkg_binary="$validation_dir/pkg-config-consumer"

  test -s "$install_prefix/lib/libsshfling.a"
  test -s "$install_prefix/lib/libsshfling.so"
  test -s "$install_prefix/include/sshfling/sshfling.h"
  test -s "$install_prefix/include/sshfling/sshfling.hpp"
  test -s "$install_prefix/lib/cmake/SSHFling/SSHFlingConfig.cmake"
  test -s "$install_prefix/lib/pkgconfig/sshfling.pc"
  test -x "$install_prefix/bin/sshfling-c"

  "$install_prefix/bin/sshfling-c" --version | grep -Fx "sshfling $version" >/dev/null
  "$install_prefix/bin/sshfling-c" init "$smoke_project" --force --session-seconds 60 >/dev/null
  test -x "$smoke_project/native/sshfling-linux-account"
  test -x "$smoke_project/native/sshfling-unix-identity"

  cmake \
    -S "$project_dir/consumers/c" \
    -B "$c_build" \
    -G Ninja \
    -DCMAKE_PREFIX_PATH="$install_prefix"
  cmake --build "$c_build"
  "$c_build/sshfling-c-consumer" "$version" | grep -Fx "sshfling $version" >/dev/null

  cmake \
    -S "$project_dir/consumers/c-static" \
    -B "$c_static_build" \
    -G Ninja \
    -DCMAKE_PREFIX_PATH="$install_prefix"
  cmake --build "$c_static_build"
  "$c_static_build/sshfling-c-static-consumer" "$version" | grep -Fx "sshfling $version" >/dev/null

  cmake \
    -S "$project_dir/consumers/cpp" \
    -B "$cpp_build" \
    -G Ninja \
    -DCMAKE_PREFIX_PATH="$install_prefix"
  cmake --build "$cpp_build"
  "$cpp_build/sshfling-cpp-consumer" "$version" | grep -Fx "sshfling $version" >/dev/null

  PKG_CONFIG_PATH="$install_prefix/lib/pkgconfig" \
    gcc "$project_dir/consumers/c/main.c" \
      $(PKG_CONFIG_PATH="$install_prefix/lib/pkgconfig" pkg-config --cflags --libs sshfling) \
      -o "$pkg_binary"
  LD_LIBRARY_PATH="$install_prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$pkg_binary" "$version" | grep -Fx "sshfling $version" >/dev/null
}

build_archive() {
  rm -f "$archive_path"
  find "$project_dir" -exec touch -h -d "@$source_date_epoch" {} +
  tar \
    --sort=name \
    --mtime="@$source_date_epoch" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --use-compress-program="gzip -n" \
    -C "$build_root" \
    -cf "$archive_path" \
    "$project_name"

  tar -tzf "$archive_path" | grep -Fx "$project_name/CMakeLists.txt" >/dev/null
  tar -tzf "$archive_path" | grep -Fx "$project_name/include/sshfling/sshfling.h" >/dev/null
  tar -tzf "$archive_path" | grep -Fx "$project_name/include/sshfling/sshfling.hpp" >/dev/null
  tar -tzf "$archive_path" | grep -Fx "$project_name/consumers/c-static/CMakeLists.txt" >/dev/null
  tar -tzf "$archive_path" | grep -Fx "$project_name/src/sshfling.c" >/dev/null
  tar -tzf "$archive_path" | grep -Fx "$project_name/runtime/sshfling.py" >/dev/null
  tar -tzf "$archive_path" | grep -Fx "$project_name/runtime/templates/native/sshfling-linux-account" >/dev/null
}

validate_removal() {
  while IFS= read -r installed; do
    rm -f "$installed"
  done <"$cmake_build/install_manifest.txt"
  find "$install_prefix" -depth -type d -empty -delete
  test ! -e "$install_prefix/bin/sshfling-c"
  test ! -e "$install_prefix/lib/libsshfling.a"
  test ! -e "$install_prefix/lib/libsshfling.so"
}

rm -rf "$build_root"
install -d "$build_root" "$validation_dir" "$dist_dir"

copy_project
build_and_install
validate_install
build_archive
validate_removal

printf '%s\n' "$archive_path"
