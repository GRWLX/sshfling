#!/usr/bin/env bash
set -euo pipefail

prefix="${PREFIX:-$HOME/.local}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template_dir="$prefix/share/fling/templates"

install -d \
  "$prefix/bin" \
  "$template_dir/scripts" \
  "$template_dir/secrets" \
  "$template_dir/ssh-client" \
  "$template_dir/ssh-server" \
  "$template_dir/production" \
  "$template_dir/systemd"

install -m 0755 "$repo_root/bin/fling" "$prefix/bin/fling"

install -m 0644 \
  "$repo_root/.env.example" \
  "$repo_root/LICENSE" \
  "$repo_root/README.md" \
  "$repo_root/compose.server.yml" \
  "$repo_root/compose.client.yml" \
  "$template_dir/"

install -m 0755 \
  "$repo_root/scripts/install-local.sh" \
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

install -m 0755 "$repo_root/production/fling-session" "$template_dir/production/fling-session"
install -m 0644 "$repo_root/systemd/flingd.service" "$template_dir/systemd/flingd.service"
install -m 0644 "$repo_root/systemd/flingd.env.example" "$template_dir/systemd/flingd.env.example"

echo "Installed fling to $prefix/bin/fling"
echo "Installed templates to $template_dir"
