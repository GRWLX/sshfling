#!/usr/bin/env bash
set -Eeuo pipefail

destination="${1:-${RUNNER_TEMP:-$PWD/build}/promoted-language-runtimes}"
download_dir="$destination/downloads"
install -d "$download_dir"

download() {
  local url="$1"
  local sha256="$2"
  local output="$3"
  if [[ ! -f "$output" ]]; then
    curl --fail --location --retry 4 --retry-all-errors --silent --show-error \
      "$url" --output "$output"
  fi
  printf '%s  %s\n' "$sha256" "$output" | sha256sum --check --status
}

install_tar() {
  local archive="$1"
  local target="$2"
  local strip_components="${3:-0}"
  rm -rf -- "$target"
  install -d "$target"
  if [[ "$strip_components" -eq 0 ]]; then
    tar -xzf "$archive" -C "$target"
  else
    tar -xzf "$archive" -C "$target" --strip-components="$strip_components"
  fi
}

install_tar_xz() {
  local archive="$1"
  local target="$2"
  rm -rf -- "$target"
  install -d "$target"
  tar -xJf "$archive" -C "$target"
}

julia_archive="$download_dir/julia-1.10.10-linux-x86_64.tar.gz"
download \
  "https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.10-linux-x86_64.tar.gz" \
  "6a78a03a71c7ab792e8673dc5cedb918e037f081ceb58b50971dfb7c64c5bf81" \
  "$julia_archive"
install_tar "$julia_archive" "$destination/julia"

j_archive="$download_dir/j9.6_linux64.tar.gz"
download \
  "https://www.jsoftware.com/download/j9.6/install/j9.6_linux64.tar.gz" \
  "e217a94ae6f4f979420ba2809c0373fb4cb8500c0441f83692ae24099813341b" \
  "$j_archive"
install_tar "$j_archive" "$destination/j"

janet_archive="$download_dir/janet-v1.41.2-linux-x64.tar.gz"
download \
  "https://github.com/janet-lang/janet/releases/download/v1.41.2/janet-v1.41.2-linux-x64.tar.gz" \
  "c09ac75730de76ad2f3e28eb054ee69c7ebb56ec95ae20234c0a0c37e57de681" \
  "$janet_archive"
install_tar "$janet_archive" "$destination/janet"
janet_root="$destination/janet/janet-v1.41.2-linux"

jpm_archive="$download_dir/jpm-907daf191ad3f1cf7e5190ec4f44eb29cd54ba21.tar.gz"
download \
  "https://codeload.github.com/janet-lang/jpm/tar.gz/907daf191ad3f1cf7e5190ec4f44eb29cd54ba21" \
  "11c4df319b18ed26946962883e7646e3d510c63b19dafb064a5060b792e549e0" \
  "$jpm_archive"
install_tar "$jpm_archive" "$destination/jpm" 1
(
  cd "$destination/jpm"
  PATH="$janet_root/bin:$PATH" \
    PREFIX="$janet_root" \
    JANET_PATH="$janet_root/lib/janet" \
    JANET_LIBPATH="$janet_root/lib" \
    "$janet_root/bin/janet" bootstrap.janet >&2
)

zig_archive="$download_dir/zig-linux-x86_64-0.13.0.tar.xz"
download \
  "https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz" \
  "d45312e61ebcc48032b77bc4cf7fd6915c11fa16e4aad116b66c9468211230ea" \
  "$zig_archive"
install_tar_xz "$zig_archive" "$destination/zig"

v_archive="$download_dir/v_linux.zip"
download \
  "https://github.com/vlang/v/releases/download/0.5.1/v_linux.zip" \
  "0c35c79343b308e0415619d8e6d8da340c6a24c18331123553cc686ffb18abf4" \
  "$v_archive"
rm -rf -- "$destination/v"
unzip -q "$v_archive" -d "$destination/v"

wasi_archive="$download_dir/wasi-sdk-33.0-x86_64-linux.tar.gz"
download \
  "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-33/wasi-sdk-33.0-x86_64-linux.tar.gz" \
  "0ba8b5bfaeb2adf3f29bab5841d76cf5318ab8e1642ea195f88baba1abd47bce" \
  "$wasi_archive"
install_tar "$wasi_archive" "$destination/wasi"
wasi_root="$destination/wasi/wasi-sdk-33.0-x86_64-linux"
install -d "$destination/bin"
wasi_clang="$wasi_root/bin/clang"
if [[ ! -x "$wasi_clang" ]]; then
  wasi_clang="$wasi_root/bin/clang-22"
fi
ln -sfn "$wasi_clang" "$destination/bin/sshfling-wasi-clang"

odin_archive="$download_dir/odin-linux-amd64-dev-2026-07.tar.gz"
download \
  "https://github.com/odin-lang/Odin/releases/download/dev-2026-07/odin-linux-amd64-dev-2026-07.tar.gz" \
  "43a497f262daac68cd09e8f2b16b7f63929d67886d90c111686239390fac6098" \
  "$odin_archive"
install_tar "$odin_archive" "$destination/odin" 1

pony_archive="$download_dir/ponyc-x86-64-unknown-linux-ubuntu24.04.tar.gz"
download \
  "https://github.com/ponylang/ponyc/releases/download/0.66.0/ponyc-x86-64-unknown-linux-ubuntu24.04.tar.gz" \
  "2de0c62974da2177d04257825c532256a928955ee38ceaf27186e68e675d8cc3" \
  "$pony_archive"
install_tar "$pony_archive" "$destination/ponyc" 1

path_entries=(
  "$destination/julia/julia-1.10.10/bin"
  "$destination/j/j9.6/bin"
  "$destination/janet/janet-v1.41.2-linux/bin"
  "$destination/zig/zig-linux-x86_64-0.13.0"
  "$destination/v/v"
  "$destination/bin"
  "$destination/odin"
  "$destination/ponyc/bin"
)

for executable in julia jconsole janet jpm zig v sshfling-wasi-clang odin ponyc; do
  found=0
  for entry in "${path_entries[@]}"; do
    if [[ -x "$entry/$executable" ]]; then
      found=1
      break
    fi
  done
  if [[ "$found" -ne 1 ]]; then
    echo "Provisioned runtime executable is missing: $executable" >&2
    exit 1
  fi
done

printf '%s\n' "$(IFS=:; echo "${path_entries[*]}")"
