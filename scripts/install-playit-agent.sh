#!/usr/bin/env bash
set -euo pipefail

[[ "$EUID" -eq 0 ]] || { echo "Run as root: sudo bash scripts/install-playit-agent.sh" >&2; exit 1; }

for cmd in curl gpg apt-get install; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing command: $cmd" >&2; exit 1; }
done

echo "[1/4] Installing the official Playit package signing key..."
install -d -m 0755 /usr/share/keyrings
curl --fail --silent --show-error --location --retry 3 \
  https://packages.playit.gg/keys/playit.gpg \
  | gpg --dearmor --yes -o /usr/share/keyrings/playit.gpg
chmod 0644 /usr/share/keyrings/playit.gpg

echo "[2/4] Adding the official Playit Debian/Ubuntu package source..."
curl --fail --silent --show-error --location --retry 3 \
  -o /etc/apt/sources.list.d/playit.list \
  https://packages.playit.gg/repo-files/playit-debian.list

echo "[3/4] Installing Playit..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y playit

echo "[4/4] Checking the systemd unit..."
if ! systemctl list-unit-files playit.service --no-legend | grep -q '^playit\.service'; then
  echo "WARNING: The package did not install playit.service on this distribution." >&2
  echo "Consult https://playit.gg/support/host-247-with-playit/ for the current service method."
else
  echo "Playit systemd unit is installed."
fi

cat <<'EOF'
Playit agent installed.

One-time account claim:
  sudo playit setup

Then create a UDP tunnel in the Playit dashboard with:
  Local/origin address: 127.0.0.1
  Local/origin port:    27015
  Tunnel type:          UDP

Start the agent at boot:
  sudo systemctl enable --now playit

Check agent status:
  sudo systemctl status playit

Keep the Playit account/agent credentials on the host; never commit them to Git.
EOF
