#!/usr/bin/env bash
set -euo pipefail

copy_sshfling_templates() {
  local src_root="$1"
  local dest="$2"

  install -d "$dest/native" "$dest/scripts" "$dest/secrets" "$dest/ssh-client" "$dest/ssh-server" "$dest/production" "$dest/systemd"

  install -m 0644 "$src_root/.env.example" "$dest/.env.example"
  install -m 0644 "$src_root/LICENSE" "$dest/LICENSE"
  install -m 0644 "$src_root/README.md" "$dest/README.md"
  install -m 0644 "$src_root/compose.server.yml" "$dest/compose.server.yml"
  install -m 0644 "$src_root/compose.client.yml" "$dest/compose.client.yml"

  install -m 0755 "$src_root/scripts/install-local.sh" "$dest/scripts/install-local.sh"
  install -m 0755 "$src_root/scripts/uninstall-local.sh" "$dest/scripts/uninstall-local.sh"
  install -m 0755 "$src_root/scripts/create-network.sh" "$dest/scripts/create-network.sh"
  install -m 0755 "$src_root/scripts/generate-ssh-key.sh" "$dest/scripts/generate-ssh-key.sh"
  install -m 0644 "$src_root/secrets/.gitkeep" "$dest/secrets/.gitkeep"

  install -m 0644 "$src_root/ssh-client/Dockerfile" "$dest/ssh-client/Dockerfile"
  install -m 0755 "$src_root/ssh-client/entrypoint.sh" "$dest/ssh-client/entrypoint.sh"

  install -m 0644 "$src_root/ssh-server/Dockerfile" "$dest/ssh-server/Dockerfile"
  install -m 0755 "$src_root/ssh-server/entrypoint.sh" "$dest/ssh-server/entrypoint.sh"
  install -m 0755 "$src_root/ssh-server/limited-session.sh" "$dest/ssh-server/limited-session.sh"
  install -m 0644 "$src_root/ssh-server/sshd_config" "$dest/ssh-server/sshd_config"

  install -m 0755 "$src_root/production/sshfling-login-shell" "$dest/production/sshfling-login-shell"
  install -m 0755 "$src_root/production/sshfling-session" "$dest/production/sshfling-session"
  install -m 0755 "$src_root/native/sshfling-linux-account" "$dest/native/sshfling-linux-account"
  install -m 0755 "$src_root/native/sshfling-unix-identity" "$dest/native/sshfling-unix-identity"
  install -m 0644 "$src_root/systemd/sshflingd.service" "$dest/systemd/sshflingd.service"
  install -m 0644 "$src_root/systemd/sshfling-prune.service" "$dest/systemd/sshfling-prune.service"
  install -m 0644 "$src_root/systemd/sshfling-prune.timer" "$dest/systemd/sshfling-prune.timer"
  install -m 0644 "$src_root/systemd/sshflingd.env.example" "$dest/systemd/sshflingd.env.example"
}
