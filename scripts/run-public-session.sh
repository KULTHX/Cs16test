#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <hlds-dir> <maxplayers> <server-log>" >&2
  exit 2
fi

HLDS_DIR="$1"
MAXPLAYERS="$2"
LOG_FILE="$3"
PLAYIT_LOG_FILE="$RUNNER_TEMP/playit-agent.log"
SSH_CONFIG="$RUNNER_TEMP/sshd_config"
SSH_PID_FILE="$RUNNER_TEMP/sshd.pid"
SSH_PID=""

if [[ -z "${PLAYIT_SECRET_KEY:-}" ]]; then
  echo "PLAYIT_SECRET_KEY is required." >&2
  exit 2
fi
# Load the public SSH keys registered in this repository.
# Optional extra keys may still be supplied through the SSH_AUTHORIZED_KEYS Actions secret.
AUTHORIZED_KEYS_FILE="${GITHUB_WORKSPACE:-}/config/ssh/authorized_keys"
if [[ -f "$AUTHORIZED_KEYS_FILE" ]]; then
  EXTRA_AUTHORIZED_KEYS="${SSH_AUTHORIZED_KEYS:-}"
  SSH_AUTHORIZED_KEYS="$(cat "$AUTHORIZED_KEYS_FILE")"
  if [[ -n "$EXTRA_AUTHORIZED_KEYS" ]]; then
    SSH_AUTHORIZED_KEYS="${SSH_AUTHORIZED_KEYS}
${EXTRA_AUTHORIZED_KEYS}"
  fi
fi
SSH_ENABLED=false
if [[ -n "${SSH_AUTHORIZED_KEYS:-}" && -n "${SSH_HOST_ED25519_PRIVATE_KEY:-}" ]]; then
  if command -v tailscale >/dev/null 2>&1 && [[ -n "$(tailscale ip -4 2>/dev/null | head -n 1)" ]]; then
    SSH_ENABLED=true
  else
    echo "SSH secrets are present, but this runner is not connected to Tailscale. SSH remains disabled."
  fi
else
  echo "Private SSH is optional. Add SSH_AUTHORIZED_KEYS and SSH_HOST_ED25519_PRIVATE_KEY Actions secrets to enable it."
fi

case "$MAXPLAYERS" in
  20|32) ;;
  *) echo "MAXPLAYERS must be 20 or 32." >&2; exit 2 ;;
esac

cd "$HLDS_DIR"
export LD_LIBRARY_PATH="$HOME/.steam/sdk32:$RUNNER_TEMP/steamcmd/linux32:${LD_LIBRARY_PATH:-}"
: > "$LOG_FILE"
: > "$PLAYIT_LOG_FILE"

# Keep one runner for a bounded session. The watchdog revives child processes
# but never chains workflows or attempts to exceed GitHub's job limit.
SESSION_LIMIT_SECONDS=20400
DEADLINE=$((SECONDS + SESSION_LIMIT_SECONDS))
SERVER_PID=""
RESTART_DELAY=15

stop_server() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -TERM -- "-$SERVER_PID" 2>/dev/null || kill -TERM "$SERVER_PID" 2>/dev/null || true
    for _ in $(seq 1 10); do
      kill -0 "$SERVER_PID" 2>/dev/null || break
      sleep 1
    done
    kill -KILL -- "-$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  SERVER_PID=""
}

stop_ssh() {
  if [[ -n "$SSH_PID" ]] && sudo kill -0 "$SSH_PID" 2>/dev/null; then
    sudo kill "$SSH_PID" 2>/dev/null || true
  fi
  SSH_PID=""
  rm -f "$SSH_PID_FILE"
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  stop_ssh
  stop_server
  docker logs --tail 200 playit > "$PLAYIT_LOG_FILE" 2>&1 || true
  docker stop playit >/dev/null 2>&1 || true
  docker rm -f playit >/dev/null 2>&1 || true
  exit "$status"
}
trap cleanup EXIT INT TERM

start_server() {
  local remaining line_start attempt status
  remaining=$((DEADLINE - SECONDS))
  if (( remaining < 240 )); then
    echo "Not enough session time remains to restart ReHLDS safely."
    return 1
  fi

  line_start=$(( $(wc -l < "$LOG_FILE") + 1 ))
  echo "Starting ReHLDS on 127.0.0.1:27015 with $MAXPLAYERS slots; $remaining seconds remain."
  setsid timeout --signal=TERM --kill-after=30s "${remaining}s" \
    ./hlds_run -game cstrike -console -ip 127.0.0.1 -port 27015 \
    +maxplayers "$MAXPLAYERS" +map de_dust2 +log on +mp_logecho 1 +sv_lan 0 \
    >> "$LOG_FILE" 2>&1 &
  SERVER_PID=$!

  for attempt in $(seq 1 90); do
    if tail -n +"$line_start" "$LOG_FILE" | grep -Eiq 'World triggered "Round_Start"'; then
      if tail -n +"$line_start" "$LOG_FILE" | grep -Eiq 'Reunion[[:space:]]+RUN'; then
        echo "ReHLDS reached Round_Start and ReUnion reports RUN."
        return 0
      fi
    fi

    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      set +e
      wait "$SERVER_PID"
      status=$?
      set -e
      SERVER_PID=""
      echo "ReHLDS exited during startup (status $status). Recent log:"
      tail -n 100 "$LOG_FILE" || true
      return 1
    fi
    sleep 2
  done

  echo "ReHLDS did not become ready within 180 seconds."
  tail -n 100 "$LOG_FILE" || true
  stop_server
  return 1
}

start_server_with_retry() {
  while (( SECONDS + 240 < DEADLINE )); do
    if start_server; then
      return 0
    fi
    echo "Watchdog: ReHLDS startup failed; retrying in $RESTART_DELAY seconds."
    sleep "$RESTART_DELAY"
  done
  return 1
}

start_playit() {
  local attempt running
  running="$(docker inspect -f '{{.State.Running}}' playit 2>/dev/null || true)"
  if [[ "$running" == "true" ]]; then
    return 0
  fi

  docker rm -f playit >/dev/null 2>&1 || true
  echo "Starting Playit UDP agent..."
  docker run -d --rm --name playit --network host \
    -e SECRET_KEY="$PLAYIT_SECRET_KEY" \
    ghcr.io/playit-cloud/playit-agent:1.0 >/dev/null || return 1

  for attempt in $(seq 1 15); do
    running="$(docker inspect -f '{{.State.Running}}' playit 2>/dev/null || true)"
    if [[ "$running" == "true" ]]; then
      docker logs --tail 40 playit || true
      return 0
    fi
    sleep 2
  done

  docker logs --tail 100 playit || true
  return 1
}

start_playit_with_retry() {
  while (( SECONDS + 60 < DEADLINE )); do
    if start_playit; then
      return 0
    fi
    echo "Watchdog: Playit agent did not stay running; retrying in $RESTART_DELAY seconds."
    sleep "$RESTART_DELAY"
  done
  return 1
}

start_ssh() {
  local ssh_user ssh_home tailscale_ip
  ssh_user="$(id -un)"
  ssh_home="$(getent passwd "$ssh_user" | cut -d: -f6)"
  if [[ -z "$ssh_home" || "$ssh_user" != "runner" ]]; then
    echo "Unexpected GitHub runner account; refusing to configure SSH for $ssh_user." >&2
    return 1
  fi

  tailscale_ip="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
  if [[ -z "$tailscale_ip" ]]; then
    echo "Tailscale IPv4 address is unavailable; refusing to expose SSH." >&2
    return 1
  fi

  sudo install -d -m 0700 -o "$ssh_user" -g "$ssh_user" "$ssh_home/.ssh"
  printf '%s\n' "$SSH_AUTHORIZED_KEYS" | sudo tee "$ssh_home/.ssh/authorized_keys" >/dev/null
  sudo chown "$ssh_user:$ssh_user" "$ssh_home/.ssh/authorized_keys"
  sudo chmod 0600 "$ssh_home/.ssh/authorized_keys"

  printf '%s\n' "$SSH_HOST_ED25519_PRIVATE_KEY" | sudo tee /etc/ssh/ssh_host_ed25519_key >/dev/null
  sudo chmod 0600 /etc/ssh/ssh_host_ed25519_key
  sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key >/dev/null

  sudo mkdir -p /run/sshd
  cat > "$SSH_CONFIG" <<EOF
Port 2222
ListenAddress $tailscale_ip
HostKey /etc/ssh/ssh_host_ed25519_key
PidFile $SSH_PID_FILE
AuthorizedKeysFile $ssh_home/.ssh/authorized_keys
AllowUsers $ssh_user
PermitRootLogin no
PubkeyAuthentication yes
AuthenticationMethods publickey
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
AllowTcpForwarding no
AllowAgentForwarding no
X11Forwarding no
PermitTunnel no
MaxAuthTries 3
LoginGraceTime 20
ClientAliveInterval 30
ClientAliveCountMax 3
LogLevel VERBOSE
EOF
  sudo /usr/sbin/sshd -t -f "$SSH_CONFIG"
  sudo /usr/sbin/sshd -f "$SSH_CONFIG"
  SSH_PID="$(sudo cat "$SSH_PID_FILE")"
  if ! sudo kill -0 "$SSH_PID" 2>/dev/null; then
    echo "SSH daemon failed to stay running." >&2
    return 1
  fi
  echo "SSH daemon is listening only on Tailscale address $tailscale_ip:2222 for key-only user $ssh_user."
}

start_ssh_with_retry() {
  local attempt
  for attempt in $(seq 1 5); do
    if start_ssh; then return 0; fi
    echo "Watchdog: SSH startup failed; retrying in 5 seconds."
    sleep 5
  done
  return 1
}

start_server_with_retry
start_playit_with_retry
if [[ "$SSH_ENABLED" == "true" ]]; then
  start_ssh_with_retry
fi

echo "Self-healing session active. The watchdog checks ReHLDS and Playit every 10 seconds."
while (( SECONDS < DEADLINE )); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    set +e
    wait "$SERVER_PID"
    server_status=$?
    set -e
    SERVER_PID=""

    echo "Watchdog: ReHLDS stopped unexpectedly (status $server_status)."
    if (( DEADLINE - SECONDS < 240 )); then
      echo "Session is near its planned end; not starting a new server process."
      break
    fi
    sleep "$RESTART_DELAY"
    start_server_with_retry
  fi

  if [[ "$SSH_ENABLED" == "true" ]]; then
    if [[ -z "$SSH_PID" ]] || ! sudo kill -0 "$SSH_PID" 2>/dev/null; then
      echo "Watchdog: SSH daemon stopped unexpectedly."
      stop_ssh
      start_ssh_with_retry
    fi
  fi

  playit_running="$(docker inspect -f '{{.State.Running}}' playit 2>/dev/null || true)"
  if [[ "$playit_running" != "true" ]]; then
    echo "Watchdog: Playit agent stopped unexpectedly."
    docker logs --tail 100 playit || true
    docker rm -f playit >/dev/null 2>&1 || true
    if (( DEADLINE - SECONDS < 60 )); then
      echo "Session is near its planned end; not restarting Playit."
      break
    fi
    sleep 5
    start_playit_with_retry
  fi

  sleep 10
done

echo "Watchdog session reached its bounded 5-hour-40-minute session budget."
