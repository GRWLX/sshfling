set -g SSHFLING_FISH_VERSION "0.0.0"

if set -q SSHFLING_PACKAGE_ROOT; and test -n "$SSHFLING_PACKAGE_ROOT"
    set -g __sshfling_fish_package_root "$SSHFLING_PACKAGE_ROOT"
else
    set -l __sshfling_fish_module_file (status current-filename)
    set -l __sshfling_fish_module_dir (dirname "$__sshfling_fish_module_file")
    set -g __sshfling_fish_package_root (cd "$__sshfling_fish_module_dir/../../.."; and pwd -P)
end

function sshfling_version
    printf '%s\n' "$SSHFLING_FISH_VERSION"
end

function sshfling_runtime_path
    if set -q SSHFLING_RUNTIME; and test -n "$SSHFLING_RUNTIME"
        printf '%s\n' "$SSHFLING_RUNTIME"
    else
        printf '%s\n' "$__sshfling_fish_package_root/libexec/sshfling/sshfling.py"
    end
end

function sshfling_template_dir
    if set -q SSHFLING_TEMPLATE_DIR; and test -n "$SSHFLING_TEMPLATE_DIR"
        printf '%s\n' "$SSHFLING_TEMPLATE_DIR"
    else
        printf '%s\n' "$__sshfling_fish_package_root/share/sshfling/templates"
    end
end

function sshfling_run
    set -l python
    if set -q SSHFLING_PYTHON; and test -n "$SSHFLING_PYTHON"
        set python "$SSHFLING_PYTHON"
    else if command -q python3
        set python (command -s python3)
    else if command -q python
        set python (command -s python)
    else
        printf '%s\n' 'sshfling: Python 3 is required; set SSHFLING_PYTHON to its executable' >&2
        return 127
    end

    set -l runtime (sshfling_runtime_path)
    set -l templates (sshfling_template_dir)
    set -l unbuffered 1
    if set -q PYTHONUNBUFFERED; and test -n "$PYTHONUNBUFFERED"
        set unbuffered "$PYTHONUNBUFFERED"
    end
    env \
        PYTHONUNBUFFERED="$unbuffered" \
        SSHFLING_TEMPLATE_DIR="$templates" \
        "$python" "$runtime" $argv
end
