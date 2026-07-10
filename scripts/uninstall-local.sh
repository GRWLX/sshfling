#!/usr/bin/env bash
set -euo pipefail

prefix="${PREFIX:-$HOME/.local}"
template_dir="$prefix/share/sshfling/templates"

remove_file() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    rm -f "$path"
    echo "Removed $path"
  fi
}

remove_empty_dir() {
  local path="$1"
  if [[ -d "$path" ]] && rmdir "$path" 2>/dev/null; then
    echo "Removed empty directory $path"
  fi
}

remove_file "$prefix/bin/sshfling"
remove_file "$prefix/libexec/sshfling/sshfling-linux-account"
remove_file "$prefix/libexec/sshfling/sshfling-unix-identity"

remove_file "$template_dir/.env.example"
remove_file "$template_dir/LICENSE"
remove_file "$template_dir/README.md"
remove_file "$template_dir/compose.server.yml"
remove_file "$template_dir/compose.client.yml"

remove_file "$template_dir/native/sshfling-linux-account"
remove_file "$template_dir/native/sshfling-unix-identity"

remove_file "$template_dir/scripts/install-local.sh"
remove_file "$template_dir/scripts/uninstall-local.sh"
remove_file "$template_dir/scripts/create-network.sh"
remove_file "$template_dir/scripts/generate-ssh-key.sh"

remove_file "$template_dir/secrets/.gitkeep"

remove_file "$template_dir/ssh-client/Dockerfile"
remove_file "$template_dir/ssh-client/entrypoint.sh"

remove_file "$template_dir/ssh-server/Dockerfile"
remove_file "$template_dir/ssh-server/sshd_config"
remove_file "$template_dir/ssh-server/entrypoint.sh"
remove_file "$template_dir/ssh-server/limited-session.sh"

remove_file "$template_dir/production/sshfling-login-shell"
remove_file "$template_dir/production/sshfling-session"

remove_file "$template_dir/systemd/sshflingd.service"
remove_file "$template_dir/systemd/sshfling-prune.service"
remove_file "$template_dir/systemd/sshfling-prune.timer"
remove_file "$template_dir/systemd/sshflingd.env.example"

remove_empty_dir "$template_dir/scripts"
remove_empty_dir "$template_dir/native"
remove_empty_dir "$template_dir/secrets"
remove_empty_dir "$template_dir/ssh-client"
remove_empty_dir "$template_dir/ssh-server"
remove_empty_dir "$template_dir/production"
remove_empty_dir "$template_dir/systemd"
remove_empty_dir "$template_dir"
remove_empty_dir "$prefix/share/sshfling"
remove_empty_dir "$prefix/libexec/sshfling"

echo "Left dependencies and files outside SSHFling local-install paths untouched."
