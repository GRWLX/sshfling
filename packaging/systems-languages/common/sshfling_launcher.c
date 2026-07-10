#define _POSIX_C_SOURCE 200809L

#include "sshfling_launcher.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
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

extern char **environ;

static const int forwarded_signals[] = {SIGHUP, SIGINT, SIGQUIT, SIGTERM};
static volatile sig_atomic_t active_child_group = -1;

struct child_environment {
    char **values;
    char *template_assignment;
    char *unbuffered_assignment;
};

struct signal_state {
    sigset_t blocked;
    sigset_t previous_mask;
    struct sigaction previous_actions[4];
    size_t action_count;
};

static char *join_path(const char *left, const char *right) {
    const size_t left_length = strlen(left);
    const size_t right_length = strlen(right);
    const int separator = left_length > 0 && left[left_length - 1] != '/';
    char *result = malloc(left_length + (size_t)separator + right_length + 1);

    if (result == NULL) {
        return NULL;
    }
    memcpy(result, left, left_length);
    if (separator != 0) {
        result[left_length] = '/';
    }
    memcpy(result + left_length + (size_t)separator, right, right_length + 1);
    return result;
}

static char *environment_assignment(const char *name, const char *value) {
    const size_t name_length = strlen(name);
    const size_t value_length = strlen(value);
    char *assignment = malloc(name_length + value_length + 2);

    if (assignment == NULL) {
        return NULL;
    }
    memcpy(assignment, name, name_length);
    assignment[name_length] = '=';
    memcpy(assignment + name_length + 1, value, value_length + 1);
    return assignment;
}

static void free_child_environment(struct child_environment *environment) {
    free(environment->template_assignment);
    free(environment->unbuffered_assignment);
    free(environment->values);
    memset(environment, 0, sizeof(*environment));
}

static int prepare_child_environment(
    const char *templates,
    struct child_environment *environment
) {
    size_t count = 0;
    size_t output = 0;

    memset(environment, 0, sizeof(*environment));
    while (environ[count] != NULL) {
        ++count;
    }
    environment->values = calloc(count + 3, sizeof(*environment->values));
    if (environment->values == NULL) {
        return -1;
    }
    for (size_t index = 0; index < count; ++index) {
        environment->values[output++] = environ[index];
    }

    if (getenv("SSHFLING_TEMPLATE_DIR") == NULL) {
        environment->template_assignment = environment_assignment(
            "SSHFLING_TEMPLATE_DIR",
            templates
        );
        if (environment->template_assignment == NULL) {
            free_child_environment(environment);
            return -1;
        }
        environment->values[output++] = environment->template_assignment;
    }
    if (getenv("PYTHONUNBUFFERED") == NULL) {
        environment->unbuffered_assignment = environment_assignment(
            "PYTHONUNBUFFERED",
            "1"
        );
        if (environment->unbuffered_assignment == NULL) {
            free_child_environment(environment);
            return -1;
        }
        environment->values[output++] = environment->unbuffered_assignment;
    }
    environment->values[output] = NULL;
    return 0;
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

static void forward_signal(int signal_number) {
    const sig_atomic_t group = active_child_group;

    if (group > 0) {
        (void)kill(-(pid_t)group, signal_number);
    }
}

static int begin_signal_forwarding(struct signal_state *state) {
    struct sigaction action;

    memset(state, 0, sizeof(*state));
    if (sigemptyset(&state->blocked) != 0) {
        return -1;
    }
    for (size_t index = 0; index < sizeof(forwarded_signals) / sizeof(forwarded_signals[0]); ++index) {
        if (sigaddset(&state->blocked, forwarded_signals[index]) != 0) {
            return -1;
        }
    }
    if (sigprocmask(SIG_BLOCK, &state->blocked, &state->previous_mask) != 0) {
        return -1;
    }

    memset(&action, 0, sizeof(action));
    action.sa_handler = forward_signal;
    action.sa_mask = state->blocked;
    for (size_t index = 0; index < sizeof(forwarded_signals) / sizeof(forwarded_signals[0]); ++index) {
        if (sigaction(forwarded_signals[index], &action, &state->previous_actions[index]) != 0) {
            for (size_t restore = 0; restore < state->action_count; ++restore) {
                (void)sigaction(
                    forwarded_signals[restore],
                    &state->previous_actions[restore],
                    NULL
                );
            }
            (void)sigprocmask(SIG_SETMASK, &state->previous_mask, NULL);
            return -1;
        }
        state->action_count += 1;
    }
    return 0;
}

static void restore_signal_state(struct signal_state *state) {
    sigset_t current_mask;

    if (sigprocmask(SIG_BLOCK, &state->blocked, &current_mask) != 0) {
        current_mask = state->previous_mask;
    }
    active_child_group = -1;
    for (size_t index = 0; index < state->action_count; ++index) {
        (void)sigaction(forwarded_signals[index], &state->previous_actions[index], NULL);
    }
    (void)sigprocmask(SIG_SETMASK, &current_mask, NULL);
}

static int spawn_python(
    const char *python,
    char *const command[],
    char *const child_environment[]
) {
    posix_spawnattr_t attributes;
    struct signal_state signal_state;
    sigset_t defaults;
    short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK;
    pid_t child = -1;
    int error;
    int status;

    if (begin_signal_forwarding(&signal_state) != 0) {
        perror("sshfling: signal setup");
        return 127;
    }
    if (posix_spawnattr_init(&attributes) != 0) {
        restore_signal_state(&signal_state);
        return 127;
    }
    defaults = signal_state.blocked;
    error = posix_spawnattr_setflags(&attributes, flags);
    if (error == 0) {
        error = posix_spawnattr_setpgroup(&attributes, 0);
    }
    if (error == 0) {
        error = posix_spawnattr_setsigdefault(&attributes, &defaults);
    }
    if (error == 0) {
        error = posix_spawnattr_setsigmask(&attributes, &signal_state.previous_mask);
    }
    if (error == 0) {
        error = posix_spawnp(
            &child,
            python,
            NULL,
            &attributes,
            command,
            child_environment
        );
    }
    (void)posix_spawnattr_destroy(&attributes);
    if (error != 0) {
        restore_signal_state(&signal_state);
        fprintf(stderr, "sshfling: could not execute %s: %s\n", python, strerror(error));
        return error == ENOENT ? 127 : 126;
    }

    active_child_group = (sig_atomic_t)child;
    if (sigprocmask(SIG_SETMASK, &signal_state.previous_mask, NULL) != 0) {
        (void)kill(-child, SIGTERM);
    }
    status = wait_for_child(child);
    restore_signal_state(&signal_state);
    return status;
}

static int python_is_version_three(const char *python) {
    static const char probe[] =
        "import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)";
    char *const command[] = {(char *)python, "-c", (char *)probe, NULL};
    pid_t child = -1;
    int error = posix_spawnp(&child, python, NULL, NULL, command, environ);

    if (error != 0) {
        return 0;
    }
    return wait_for_child(child) == 0;
}

static const char *select_python(void) {
    const char *configured = getenv("SSHFLING_PYTHON");

    if (configured != NULL && configured[0] != '\0') {
        if (python_is_version_three(configured)) {
            return configured;
        }
        fprintf(stderr, "sshfling: SSHFLING_PYTHON is not a working Python 3 executable: %s\n", configured);
        return NULL;
    }
    if (python_is_version_three("python3")) {
        return "python3";
    }
    if (python_is_version_three("python")) {
        return "python";
    }
    fputs("sshfling: Python 3 is required; set SSHFLING_PYTHON to its executable\n", stderr);
    return NULL;
}

static int run_python(
    const char *python,
    const char *script,
    const char *templates,
    size_t argc,
    const char *const argv[]
) {
    struct child_environment environment;
    char **command = calloc(argc + 3, sizeof(*command));
    int status;

    if (command == NULL) {
        fputs("sshfling: could not allocate command arguments\n", stderr);
        return 127;
    }
    command[0] = (char *)python;
    command[1] = (char *)script;
    for (size_t index = 0; index < argc; ++index) {
        command[index + 2] = (char *)argv[index];
    }
    if (prepare_child_environment(templates, &environment) != 0) {
        free(command);
        fputs("sshfling: could not prepare child environment\n", stderr);
        return 127;
    }

    status = spawn_python(python, command, environment.values);
    free_child_environment(&environment);
    free(command);
    return status;
}

const char *sshfling_launcher_version(void) {
    return SSHFLING_VERSION;
}

int sshfling_launcher_run(size_t argc, const char *const argv[]) {
    const char *runtime;
    const char *python;
    char *script;
    char *templates;
    int status;

    if (argc > 0 && argv == NULL) {
        fputs("sshfling: invalid launcher arguments\n", stderr);
        return 2;
    }
    for (size_t index = 0; index < argc; ++index) {
        if (argv[index] == NULL) {
            fputs("sshfling: invalid launcher arguments\n", stderr);
            return 2;
        }
    }

    runtime = getenv("SSHFLING_RUNTIME_DIR");
    if (runtime == NULL || runtime[0] == '\0') {
        runtime = SSHFLING_INSTALL_RUNTIME_DIR;
    }
    script = join_path(runtime, "sshfling.py");
    templates = join_path(runtime, "templates");
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

    python = select_python();
    if (python == NULL) {
        free(script);
        free(templates);
        return 127;
    }
    status = run_python(python, script, templates, argc, argv);
    free(script);
    free(templates);
    return status;
}

int sshfling_launcher_main(int argc, char *const argv[]) {
    if (argc < 1 || argv == NULL) {
        fputs("sshfling: invalid launcher arguments\n", stderr);
        return 2;
    }
    return sshfling_launcher_run((size_t)(argc - 1), (const char *const *)(argv + 1));
}

int sshfling_launcher_run_nul(size_t argc, const char *arguments) {
    const char **argv;
    const char *cursor = arguments;
    int status;

    if (argc > 0 && arguments == NULL) {
        return 2;
    }
    argv = calloc(argc == 0 ? 1 : argc, sizeof(*argv));
    if (argv == NULL) {
        return 127;
    }
    for (size_t index = 0; index < argc; ++index) {
        argv[index] = cursor;
        cursor += strlen(cursor) + 1;
    }
    status = sshfling_launcher_run(argc, argv);
    free(argv);
    return status;
}

int sshfling_launcher_run_strided(size_t argc, const char *arguments, size_t stride) {
    const char **argv;
    int status;

    if ((argc > 0 && arguments == NULL) || (argc > 1 && stride == 0)) {
        return 2;
    }
    argv = calloc(argc == 0 ? 1 : argc, sizeof(*argv));
    if (argv == NULL) {
        return 127;
    }
    for (size_t index = 0; index < argc; ++index) {
        argv[index] = arguments + (index * stride);
    }
    status = sshfling_launcher_run(argc, argv);
    free(argv);
    return status;
}

int sshfling_launcher_run_process_arguments(void) {
#if defined(__linux__)
    const size_t chunk_size = 4096;
    size_t capacity = chunk_size;
    size_t length = 0;
    char *buffer = malloc(capacity);
    const char **arguments = NULL;
    size_t argument_count = 0;
    int descriptor;
    int status;

    if (buffer == NULL) {
        return 127;
    }
    descriptor = open("/proc/self/cmdline", O_RDONLY | O_CLOEXEC);
    if (descriptor < 0) {
        free(buffer);
        return 127;
    }
    for (;;) {
        ssize_t read_count;

        if (length == capacity) {
            size_t next_capacity;
            char *next;

            if (capacity > SIZE_MAX / 2) {
                (void)close(descriptor);
                free(buffer);
                return 127;
            }
            next_capacity = capacity * 2;
            next = realloc(buffer, next_capacity);
            if (next == NULL) {
                (void)close(descriptor);
                free(buffer);
                return 127;
            }
            buffer = next;
            capacity = next_capacity;
        }
        read_count = read(descriptor, buffer + length, capacity - length);
        if (read_count < 0) {
            if (errno == EINTR) {
                continue;
            }
            (void)close(descriptor);
            free(buffer);
            return 127;
        }
        if (read_count == 0) {
            break;
        }
        length += (size_t)read_count;
    }
    (void)close(descriptor);
    if (length == 0 || buffer[length - 1] != '\0') {
        free(buffer);
        return 127;
    }
    for (size_t index = 0; index < length; ++index) {
        if (buffer[index] == '\0') {
            ++argument_count;
        }
    }
    if (argument_count == 0) {
        free(buffer);
        return 2;
    }
    arguments = calloc(argument_count, sizeof(*arguments));
    if (arguments == NULL) {
        free(buffer);
        return 127;
    }
    arguments[0] = buffer;
    for (size_t index = 1, offset = 0; index < argument_count; ++index) {
        offset += strlen(buffer + offset) + 1;
        arguments[index] = buffer + offset;
    }
    status = sshfling_launcher_run(argument_count - 1, arguments + 1);
    free(arguments);
    free(buffer);
    return status;
#else
    fputs("sshfling: exact process argument recovery is available only on Linux\n", stderr);
    return 127;
#endif
}
