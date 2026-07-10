typeset -g SSHFLING_ZSH_VERSION="0.0.0"
typeset -g __SSHFLING_ZSH_MODULE_FILE="${${(%):-%N}:A}"

if [[ -n "${SSHFLING_PACKAGE_ROOT:-}" ]]; then
  typeset -g __SSHFLING_ZSH_PACKAGE_ROOT="${SSHFLING_PACKAGE_ROOT:A}"
else
  typeset -g __SSHFLING_ZSH_PACKAGE_ROOT="${__SSHFLING_ZSH_MODULE_FILE:h:h:h:h}"
fi

sshfling_version() {
  print -r -- "$SSHFLING_ZSH_VERSION"
}

sshfling_runtime_path() {
  if [[ -n "${SSHFLING_RUNTIME:-}" ]]; then
    print -r -- "$SSHFLING_RUNTIME"
  else
    print -r -- "$__SSHFLING_ZSH_PACKAGE_ROOT/libexec/sshfling/sshfling.py"
  fi
}

sshfling_template_dir() {
  if [[ -n "${SSHFLING_TEMPLATE_DIR:-}" ]]; then
    print -r -- "$SSHFLING_TEMPLATE_DIR"
  else
    print -r -- "$__SSHFLING_ZSH_PACKAGE_ROOT/share/sshfling/templates"
  fi
}

sshfling_run() {
  local python
  if [[ -n "${SSHFLING_PYTHON:-}" ]]; then
    python="$SSHFLING_PYTHON"
  elif (( ${+commands[python3]} )); then
    python="$commands[python3]"
  elif (( ${+commands[python]} )); then
    python="$commands[python]"
  else
    print -u2 -r -- "sshfling: Python 3 is required; set SSHFLING_PYTHON to its executable"
    return 127
  fi

  local runtime="$(sshfling_runtime_path)"
  local templates="$(sshfling_template_dir)"
  PYTHONUNBUFFERED="${PYTHONUNBUFFERED:-1}" \
    SSHFLING_TEMPLATE_DIR="$templates" \
    command "$python" "$runtime" "$@"
}
