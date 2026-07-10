# POSIX AWK source integration for the bundled SSHFling runtime.
# Load with: awk -f sshfling.awk -f consumer.awk

function sshfling_version() {
    return "0.0.0"
}

function sshfling_package_root() {
    return ENVIRON["SSHFLING_PACKAGE_ROOT"]
}

function sshfling_runtime_path(    root) {
    if (ENVIRON["SSHFLING_RUNTIME"] != "") {
        return ENVIRON["SSHFLING_RUNTIME"]
    }
    root = sshfling_package_root()
    return root == "" ? "" : root "/libexec/sshfling/sshfling.py"
}

function sshfling_template_dir(    root) {
    if (ENVIRON["SSHFLING_TEMPLATE_DIR"] != "") {
        return ENVIRON["SSHFLING_TEMPLATE_DIR"]
    }
    root = sshfling_package_root()
    return root == "" ? "" : root "/share/sshfling/templates"
}

function sshfling_python() {
    return ENVIRON["SSHFLING_PYTHON"] == "" ? "python3" : ENVIRON["SSHFLING_PYTHON"]
}

function sshfling_shell_quote(value,    character, i, quoted, single_quote) {
    single_quote = sprintf("%c", 39)
    quoted = single_quote
    for (i = 1; i <= length(value); i++) {
        character = substr(value, i, 1)
        if (character == single_quote) {
            quoted = quoted single_quote "\\" single_quote single_quote
        } else {
            quoted = quoted character
        }
    }
    return quoted single_quote
}

function sshfling_run(arguments, argument_count,    command, error_command, i, runtime, status, templates) {
    runtime = sshfling_runtime_path()
    templates = sshfling_template_dir()
    if (runtime == "" || templates == "") {
        error_command = "cat >&2"
        print "sshfling: set SSHFLING_PACKAGE_ROOT, or set SSHFLING_RUNTIME and SSHFLING_TEMPLATE_DIR" | error_command
        close(error_command)
        return 127
    }

    command = "PYTHONUNBUFFERED=1 SSHFLING_TEMPLATE_DIR=" sshfling_shell_quote(templates)
    command = command " " sshfling_shell_quote(sshfling_python())
    command = command " " sshfling_shell_quote(runtime)
    for (i = 1; i <= argument_count; i++) {
        command = command " " sshfling_shell_quote(arguments[i])
    }

    status = system(command)
    if (status < 0) {
        return 127
    }
    if (status > 255) {
        return int(status / 256)
    }
    return status
}
