#!/usr/bin/env bash
set -euo pipefail

network_name="${1:-timed-ssh-net}"

if docker network inspect "$network_name" >/dev/null 2>&1; then
  echo "Docker network already exists: $network_name"
else
  docker network create "$network_name" >/dev/null
  echo "Created Docker network: $network_name"
fi
