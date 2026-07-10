#!/usr/bin/env bash
set -Eeuo pipefail

destination="${1:-${RUNNER_TEMP:-$PWD/build}/promoted-language-runtimes}"
install -d "$destination"
destination="$(cd "$destination" && pwd)"
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

install_deb() {
  local archive="$1"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    apt-get install -y --no-install-recommends "$archive" >&2
  elif command -v sudo >/dev/null 2>&1; then
    sudo apt-get install -y --no-install-recommends "$archive" >&2
  else
    echo "sudo or root privileges are required to install $archive" >&2
    exit 1
  fi
}

extract_deb() {
  local archive="$1"
  local target="$2"
  dpkg-deb -x "$archive" "$target"
}

ballerina_deb="$download_dir/ballerina-2201.12.0-swan-lake-linux-x64.deb"
download \
  "https://github.com/ballerina-platform/ballerina-distribution/releases/download/v2201.12.0/ballerina-2201.12.0-swan-lake-linux-x64.deb" \
  "ba6e36d8da15ee3c244f5485ad40b3db5b7bdaa9220263f8fdd0e9276fc81734" \
  "$ballerina_deb"
if ! command -v bal >/dev/null 2>&1 || ! bal version 2>/dev/null | grep -F "Ballerina 2201.12.0" >/dev/null; then
  install_deb "$ballerina_deb"
fi

chapel_deb="$download_dir/chapel-2.4.0-1.ubuntu24.amd64.deb"
download \
  "https://github.com/chapel-lang/chapel/releases/download/2.4.0/chapel-2.4.0-1.ubuntu24.amd64.deb" \
  "368809ea039c5a04e282237e210ff9d7f7edabdc15706f008707ca65698349f1" \
  "$chapel_deb"
if ! command -v chpl >/dev/null 2>&1 || ! chpl --version 2>/dev/null | grep -F "chpl version 2.4.0" >/dev/null; then
  install_deb "$chapel_deb"
fi

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

harbour_archive="$download_dir/harbour-core-6df4c08b98c808904e0c19effbc09523af010ed6.tar.gz"
download \
  "https://codeload.github.com/harbour/core/tar.gz/6df4c08b98c808904e0c19effbc09523af010ed6" \
  "0316216fe12af25a0275f31349dc9538b05720b018b6e0230a21ffa8649f457e" \
  "$harbour_archive"
if [[ ! -x "$destination/harbour/bin/harbour" || ! -x "$destination/harbour/bin/hbmk2" ]]; then
  install_tar "$harbour_archive" "$destination/harbour-src" 1
  (
    cd "$destination/harbour-src"
    make -j"${HARBOUR_BUILD_JOBS:-$(nproc)}" install \
      HB_INSTALL_PREFIX="$destination/harbour" \
      HB_BUILD_CONTRIBS=no \
      HB_BUILD_3RDEXT=no \
      HB_BUILD_SHARED=no \
      HB_BUILD_STRIP=bin >&2
  )
fi

ring_commit="f88d95236319460327b05efcfdab7c342caa7d22"
ring_source="$destination/ring-src"
ring_bin="$destination/ring/bin/ring"
if [[ ! -x "$ring_bin" ]] || ! "$ring_bin" -version 2>/dev/null | grep -F "Ring version 1.27.0" >/dev/null; then
  rm -rf -- "$ring_source" "$destination/ring"
  git clone --depth 1 --filter=blob:none --sparse --branch v1.27 \
    https://github.com/ring-lang/ring.git "$ring_source" >&2
  (
    cd "$ring_source"
    if [[ "$(git rev-parse HEAD)" != "$ring_commit" ]]; then
      echo "Ring v1.27 commit verification failed" >&2
      exit 1
    fi
    git sparse-checkout set language/src language/include bin/load >&2
    install -d "$(dirname "$ring_bin")"
    cp -a bin/load "$(dirname "$ring_bin")/load"
    cd language/src
    gcc -O2 \
      ring.c general.c state.c ext.c hashlib.c rhtable.c vmgc.c os_e.c rstring.c \
      rlist.c ritem.c ritems.c scanner.c parser.c stmt.c expr.c codegen.c vm.c \
      vmerror.c vmeval.c vmthread.c vmexpr.c vmvars.c vmlists.c vmfuncs.c \
      ringapi.c vmoop.c vmtry.c vmstr.c vmjump.c vmrange.c list_e.c meta_e.c \
      vminfo_e.c vmperf.c vmexit.c vmstack.c vmstate.c genlib_e.c math_e.c \
      file_e.c dll_e.c objfile.c \
      -I "$PWD/../include" -o "$ring_bin" -lm -ldl >&2
  )
fi

red_binary="$download_dir/red-toolchain-066"
download \
  "https://static.red-lang.org/dl/linux/red-toolchain-066" \
  "95c75a49f8b3d15b8ae1ddf10f9589bc0fd0eecf84d432bad163191f900cb23c" \
  "$red_binary"
install -d "$destination/red/bin"
install -m 0755 "$red_binary" "$destination/red/bin/red"

roc_archive="$download_dir/roc-linux_x86_64-alpha4-rolling.tar.gz"
download \
  "https://github.com/roc-lang/roc/releases/download/alpha4-rolling/roc-linux_x86_64-alpha4-rolling.tar.gz" \
  "96e8be05e6f7176433ada74532ff36a62b8dc44c5247a82cdf919f2dadc5178b" \
  "$roc_archive"
install_tar "$roc_archive" "$destination/roc"
roc_root="$(find "$destination/roc" -mindepth 1 -maxdepth 1 -type d -name 'roc_nightly-*' -print -quit)"
if [[ -z "$roc_root" || ! -x "$roc_root/roc" ]]; then
  echo "Roc toolchain archive did not contain an executable roc binary" >&2
  exit 1
fi

smalltalk_root="$destination/smalltalk"
rm -rf -- "$smalltalk_root"
install -d "$smalltalk_root"
smalltalk_debs=(
  "https://deb.debian.org/debian/pool/main/g/gnu-smalltalk/gnu-smalltalk_3.2.5-1.3+b2_amd64.deb b39305547cb05754aecd94adf683e92f907cbb9259fd667e851651d69d558f35"
  "https://deb.debian.org/debian/pool/main/g/gnu-smalltalk/libgst7_3.2.5-1.3+b2_amd64.deb 1e2973879aaf4a89555a10c7945b896348715c9c4b5da9cd10433c3ea8873af0"
  "https://deb.debian.org/debian/pool/main/g/gnu-smalltalk/gnu-smalltalk-common_3.2.5-1.3_all.deb 24a86c61b9de359001729bf83600bb91eba1443dd114bd1eb8ba88167a641db4"
  "https://deb.debian.org/debian/pool/main/libf/libffi/libffi7_3.3-6_amd64.deb 30ca89bfddae5fa6e0a2a044f22b6e50cd17c4bc6bc850c579819aeab7101f0f"
  "https://deb.debian.org/debian/pool/main/g/gmp/libgmp10_6.2.1+dfsg-1+deb11u1_amd64.deb fc117ccb084a98d25021f7e01e4dfedd414fa2118fdd1e27d2d801d7248aebbc"
  "https://deb.debian.org/debian/pool/main/libt/libtool/libltdl7_2.4.6-15_amd64.deb 52a0a21e06bb89038a3ab6949020228fbf9dd7897e027233cf0a8c2d111d6c10"
  "https://deb.debian.org/debian/pool/main/r/readline/libreadline8_8.1-1_amd64.deb 162ba9fdcde81b5502953ed4d84b24e8ad4e380bbd02990ab1a0e3edffca3c22"
  "https://deb.debian.org/debian/pool/main/libs/libsigsegv/libsigsegv2_2.13-1_amd64.deb c56a7108e1c6dca27b4db9cce5c7c2b0c9d961b3572a1d1fe89058388401bd2b"
)
for entry in "${smalltalk_debs[@]}"; do
  read -r url sha256 <<<"$entry"
  archive="$download_dir/${url##*/}"
  download "$url" "$sha256" "$archive"
  extract_deb "$archive" "$smalltalk_root"
done
install -d "$smalltalk_root/bin"
cat >"$smalltalk_root/bin/gst" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LD_LIBRARY_PATH="$root/usr/lib/x86_64-linux-gnu:$root/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$root/usr/bin/gst" --kernel-directory "$root/usr/share/gnu-smalltalk/kernel" "$@"
EOF
cat >"$smalltalk_root/bin/gst-package" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LD_LIBRARY_PATH="$root/usr/lib/x86_64-linux-gnu:$root/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$root/usr/bin/gst-package" --kernel-dir="$root/usr/share/gnu-smalltalk/kernel" -I "$root/usr/lib/gnu-smalltalk/gst.im" "$@"
EOF
chmod +x "$smalltalk_root/bin/gst" "$smalltalk_root/bin/gst-package"

apl_root="$destination/apl"
apl_deb="$download_dir/apl_2.0-1_amd64.deb"
download \
  "https://ftp.gnu.org/gnu/apl/apl_2.0-1_amd64.deb" \
  "eb09ce5761a8c989f1993d451200527a3ebf0f253543e1aaf8fbe53b6a9bdb7b" \
  "$apl_deb"
rm -rf -- "$apl_root"
install -d "$apl_root"
extract_deb "$apl_deb" "$apl_root"

path_entries=(
  "$destination/julia/julia-1.10.10/bin"
  "$destination/j/j9.6/bin"
  "$destination/janet/janet-v1.41.2-linux/bin"
  "$destination/zig/zig-linux-x86_64-0.13.0"
  "$destination/v/v"
  "$destination/bin"
  "$destination/odin"
  "$destination/ponyc/bin"
  "$destination/harbour/bin"
  "$destination/ring/bin"
  "$destination/red/bin"
  "$roc_root"
  "$destination/smalltalk/bin"
  "$destination/apl/usr/bin"
  "/usr/bin"
)

for executable in julia jconsole janet jpm zig v sshfling-wasi-clang odin ponyc harbour hbmk2 ring red roc gst gst-package apl bal chpl mason; do
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
