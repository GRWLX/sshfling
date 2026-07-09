#define _POSIX_C_SOURCE 200809L

#include <sshfling/sshfling.h>

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef SSHFLING_VERSION
#define SSHFLING_VERSION "0.0.0"
#endif

#ifndef SSHFLING_INSTALL_RUNTIME_DIR
#define SSHFLING_INSTALL_RUNTIME_DIR "/usr/local/share/sshfling"
#endif

static char *join_path(const char *left, const char *right) {
    size_t left_length = strlen(left);
    size_t right_length = strlen(right);
    int needs_separator = left_length > 0 && left[left_length - 1] != '/';
    char *result = malloc(left_length + (size_t)needs_separator + right_length + 1);
    if (result == NULL) {
        return NULL;
    }
    memcpy(result, left, left_length);
    if (needs_separator) {
        result[left_length++] = '/';
    }
    memcpy(result + left_length, right, right_length + 1);
    return result;
}

static int executable_available(const char *program) {
    if (strchr(program, '/') != NULL) {
        return access(program, X_OK) == 0;
    }

    const char *path_value = getenv("PATH");
    if (path_value == NULL) {
        return 0;
    }
    char *path_copy = strdup(path_value);
    if (path_copy == NULL) {
        return 0;
    }

    int found = 0;
    char *cursor = path_copy;
    while (cursor != NULL) {
        char *separator = strchr(cursor, ':');
        if (separator != NULL) {
            *separator = '\0';
        }
        const char *directory = cursor[0] == '\0' ? "." : cursor;
        char *candidate = join_path(directory, program);
        if (candidate != NULL && access(candidate, X_OK) == 0) {
            found = 1;
        }
        free(candidate);
        if (found || separator == NULL) {
            break;
        }
        cursor = separator + 1;
    }
    free(path_copy);
    return found;
}

static int wait_for_child(pid_t child) {
    int status = 0;
    while (waitpid(child, &status, 0) < 0) {
        if (errno == EINTR) {
            continue;
        }
        perror("sshfling: waitpid");
        return 127;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return 1;
}

static int run_python(
    const char *python,
    const char *script,
    const char *templates,
    size_t argc,
    const char *const argv[]
) {
    char **command = calloc(argc + 3, sizeof(*command));
    if (command == NULL) {
        fputs("sshfling: could not allocate command arguments\n", stderr);
        return 127;
    }
    command[0] = (char *)python;
    command[1] = (char *)script;
    for (size_t index = 0; index < argc; ++index) {
        command[index + 2] = (char *)argv[index];
    }

    pid_t child = fork();
    if (child < 0) {
        perror("sshfling: fork");
        free(command);
        return 127;
    }
    if (child == 0) {
        if (getenv("SSHFLING_TEMPLATE_DIR") == NULL) {
            setenv("SSHFLING_TEMPLATE_DIR", templates, 1);
        }
        if (getenv("PYTHONUNBUFFERED") == NULL) {
            setenv("PYTHONUNBUFFERED", "1", 1);
        }
        execvp(python, command);
        if (errno != ENOENT) {
            fprintf(stderr, "sshfling: could not execute %s: %s\n", python, strerror(errno));
        }
        _exit(errno == ENOENT ? 127 : 126);
    }

    free(command);
    return wait_for_child(child);
}

const char *sshfling_version(void) {
    return SSHFLING_VERSION;
}

int sshfling_run_with_python(const char *python, size_t argc, const char *const argv[]) {
    if (python == NULL || python[0] == '\0' || (argc > 0 && argv == NULL)) {
        fputs("sshfling: invalid launcher arguments\n", stderr);
        return 2;
    }

    const char *runtime = getenv("SSHFLING_C_RUNTIME_DIR");
    if (runtime == NULL || runtime[0] == '\0') {
        runtime = SSHFLING_INSTALL_RUNTIME_DIR;
    }
    char *script = join_path(runtime, "sshfling.py");
    char *templates = join_path(runtime, "templates");
    if (script == NULL || templates == NULL) {
        free(script);
        free(templates);
        fputs("sshfling: could not allocate runtime paths\n", stderr);
        return 127;
    }
    if (access(script, R_OK) != 0 || access(templates, R_OK | X_OK) != 0) {
        fprintf(stderr, "sshfling: bundled runtime is unavailable under %s\n", runtime);
        free(script);
        free(templates);
        return 127;
    }

    int status = run_python(python, script, templates, argc, argv);
    free(script);
    free(templates);
    return status;
}

int sshfling_run(size_t argc, const char *const argv[]) {
    const char *configured = getenv("SSHFLING_PYTHON");
    if (configured != NULL && configured[0] != '\0') {
        return sshfling_run_with_python(configured, argc, argv);
    }

    if (executable_available("python3")) {
        return sshfling_run_with_python("python3", argc, argv);
    }
    if (executable_available("python")) {
        return sshfling_run_with_python("python", argc, argv);
    }
    fputs("sshfling: Python 3 is required; set SSHFLING_PYTHON to its executable\n", stderr);
    return 127;
}
