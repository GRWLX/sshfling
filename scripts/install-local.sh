#!/usr/bin/env bash
set -euo pipefail

prefix="${PREFIX:-$HOME/.local}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template_dir="$prefix/share/sshfling/templates"

install -d \
  "$prefix/bin" \
  "$prefix/libexec/sshfling" \
  "$template_dir/native" \
  "$template_dir/scripts" \
  "$template_dir/secrets" \
  "$template_dir/ssh-client" \
  "$template_dir/ssh-server" \
  "$template_dir/production" \
  "$template_dir/systemd"

install -m 0755 "$repo_root/bin/sshfling" "$prefix/bin/sshfling"
install -m 0755 "$repo_root/native/sshfling-linux-account" "$prefix/libexec/sshfling/sshfling-linux-account"
install -m 0755 "$repo_root/native/sshfling-unix-identity" "$prefix/libexec/sshfling/sshfling-unix-identity"
install -m 0755 "$repo_root/native/sshfling-linux-account" "$template_dir/native/sshfling-linux-account"
install -m 0755 "$repo_root/native/sshfling-unix-identity" "$template_dir/native/sshfling-unix-identity"

install -m 0644 \
  "$repo_root/.env.example" \
  "$repo_root/LICENSE" \
  "$repo_root/README.md" \
  "$repo_root/compose.server.yml" \
  "$repo_root/compose.client.yml" \
  "$template_dir/"

install -m 0755 \
  "$repo_root/scripts/install-local.sh" \
  "$repo_root/scripts/uninstall-local.sh" \
  "$repo_root/scripts/create-network.sh" \
  "$repo_root/scripts/generate-ssh-key.sh" \
  "$template_dir/scripts/"

install -m 0644 "$repo_root/secrets/.gitkeep" "$template_dir/secrets/.gitkeep"

install -m 0644 "$repo_root/ssh-client/Dockerfile" "$template_dir/ssh-client/Dockerfile"
install -m 0755 "$repo_root/ssh-client/entrypoint.sh" "$template_dir/ssh-client/entrypoint.sh"

install -m 0644 \
  "$repo_root/ssh-server/Dockerfile" \
  "$repo_root/ssh-server/sshd_config" \
  "$template_dir/ssh-server/"

install -m 0755 \
  "$repo_root/ssh-server/entrypoint.sh" \
  "$repo_root/ssh-server/limited-session.sh" \
  "$template_dir/ssh-server/"

install -m 0755 "$repo_root/production/sshfling-session" "$template_dir/production/sshfling-session"
install -m 0644 "$repo_root/systemd/sshflingd.service" "$template_dir/systemd/sshflingd.service"
install -m 0644 "$repo_root/systemd/sshfling-prune.service" "$template_dir/systemd/sshfling-prune.service"
install -m 0644 "$repo_root/systemd/sshfling-prune.timer" "$template_dir/systemd/sshfling-prune.timer"
install -m 0644 "$repo_root/systemd/sshflingd.env.example" "$template_dir/systemd/sshflingd.env.example"

echo "Installed sshfling to $prefix/bin/sshfling"
echo "Installed native Linux account backend to $prefix/libexec/sshfling"
echo "Installed native Unix identity backend to $prefix/libexec/sshfling"
echo "Installed templates to $template_dir"
