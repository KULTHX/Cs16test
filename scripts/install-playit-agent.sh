#!/usr/bin/env bash
set -euo pipefail

[[ "$EUID" -eq 0 ]] || { echo "Run as root: sudo bash scripts/install-playit-agent.sh" >&2; exit 1; }

for cmd in curl gpg apt-get install; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing command: $cmd" >&2; exit 1; }
done

install -d -m 0755 /etc/apt/keyrings
curl --fail --location --retry 3 https://playit-cloud.github.io/ppa/key.gpg \
  | gpg --dearmor --yes -o /etc/apt/keyrings/playit.gpg
chmod 0644 /etc/apt/keyrings/playit.gpg

cat > /etc/apt/sources.list.d/playit-cloud.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/playit.gpg] https://playit-cloud.github.io/ppa/data ./
EOF

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y playit

cat <<'EOF'
Playit agent installed.

One-time account claim:
  sudo playit setup

After the agent is claimed and the UDP tunnel is created in the Playit dashboard:
  sudo systemctl enable --now playit
  sudo systemctl status playit

Create a UDP tunnel with local/origin address 127.0.0.1 and local port 27015.
Do not put the Playit agent key or account token in this repository.
EOF
