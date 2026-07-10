#!/bin/sh
set -eu

script_path=$0
while [ -L "$script_path" ]; do
    link_target=$(readlink "$script_path") || exit 127
    case "$link_target" in
        /*) script_path=$link_target ;;
        *) script_path=$(dirname "$script_path")/$link_target ;;
    esac
done
script_dir=$(CDPATH='' cd -P "$(dirname "$script_path")" && pwd)
package_root=$(CDPATH='' cd -P "$script_dir/.." && pwd)
runtime=$package_root/libexec/sshfling/sshfling.py
bundled_templates=$package_root/share/sshfling/templates

if [ ! -f "$runtime" ] || [ ! -d "$bundled_templates" ]; then
    echo "sshfling: packaged runtime or templates are missing" >&2
    exit 127
fi

if [ -n "${SSHFLING_PYTHON:-}" ]; then
    python=$SSHFLING_PYTHON
elif command -v python3 >/dev/null 2>&1; then
    python=python3
elif command -v python >/dev/null 2>&1; then
    python=python
else
    echo "sshfling: Python 3 is required; set SSHFLING_PYTHON to its executable" >&2
    exit 127
fi

if ! command -v "$python" >/dev/null 2>&1; then
    echo "sshfling: Python executable not found: $python" >&2
    exit 127
fi

if [ -z "${SSHFLING_TEMPLATE_DIR:-}" ]; then
    SSHFLING_TEMPLATE_DIR=$bundled_templates
    export SSHFLING_TEMPLATE_DIR
fi
PYTHONUNBUFFERED=${PYTHONUNBUFFERED:-1}
export PYTHONUNBUFFERED

exec "$python" "$runtime" "$@"
