#include <stdint.h>

#if !defined(__wasm__)
#error "sshfling-wasi must be compiled for a WebAssembly target"
#endif

__attribute__((import_module("sshfling:launcher"), import_name("run")))
extern int32_t sshfling_host_run(int32_t argc, const char *const argv[]);

__attribute__((visibility("default")))
const char *sshfling_wasi_version(void) {
    return "0.0.0";
}

__attribute__((visibility("default")))
int sshfling_wasi_run(int argc, const char *const argv[]) {
    return sshfling_host_run((int32_t)argc, argv);
}

int main(int argc, char **argv) {
    return sshfling_wasi_run(argc - 1, (const char *const *)(argv + 1));
}
