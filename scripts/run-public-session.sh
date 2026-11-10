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
BORE_LOG_FILE="$RUNNER_TEMP/bore.log"
SSH_CONFIG="$RUNNER_TEMP/sshd_config"
SSH_PID_FILE="$RUNNER_TEMP/sshd.pid"
SSH_PID=""

if [[ -z "${PLAYIT_SECRET_KEY:-}" ]]; then
  echo "PLAYIT_SECRET_KEY is required." >&2
  exit 2
fi
# Load the public SSH keys registered in this repository.
AUTHORIZED_KEYS_FILE="${GITHUB_WORKSPACE:-}/config/ssh/authorized_keys"
SSH_AUTHORIZED_KEYS=""
if [[ -s "$AUTHORIZED_KEYS_FILE" ]]; then
  SSH_AUTHORIZED_KEYS="$(cat "$AUTHORIZED_KEYS_FILE")"
  SSH_ENABLED=true
else
  SSH_ENABLED=false
  echo "No SSH public keys found; Bore SSH access will be skipped."
fi
BORE_ENABLED=false
BORE_LOG_PID=""
BORE_ADDRESS=""
BORE_PORT=""
SSH_HOST_FINGERPRINT=""
case "$MAXPLAYERS" in
  20|32) ;;
  *) echo "MAXPLAYERS must be 20 or 32." >&2; exit 2 ;;
esac

cd "$HLDS_DIR"
# Intentionally remove the generated/base server.cfg so it cannot override Zombie Plague settings.
rm -f "$HLDS_DIR/cstrike/server.cfg"
export LD_LIBRARY_PATH="$HOME/.steam/sdk32:$RUNNER_TEMP/steamcmd/linux32:${LD_LIBRARY_PATH:-}"
: > "$LOG_FILE"
: > "$PLAYIT_LOG_FILE"
: > "$BORE_LOG_FILE"

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

stop_bore() {
  if [[ -n "$BORE_LOG_PID" ]] && kill -0 "$BORE_LOG_PID" 2>/dev/null; then
    kill "$BORE_LOG_PID" 2>/dev/null || true
    wait "$BORE_LOG_PID" 2>/dev/null || true
  fi
  BORE_LOG_PID=""
  docker stop bore >/dev/null 2>&1 || true
  docker rm -f bore >/dev/null 2>&1 || true
  BORE_ADDRESS=""
  BORE_PORT=""
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  stop_bore
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
  local start_map candidate
  start_map="de_dust2"
  if [[ -f "$HLDS_DIR/cstrike/mapcycle.txt" ]]; then
    while IFS= read -r candidate; do
      candidate="${candidate%%#*}"
      candidate="${candidate//[[:space:]]/}"
      if [[ "$candidate" =~ ^[A-Za-z0-9_]+$ && -f "$HLDS_DIR/cstrike/maps/$candidate.bsp" ]]; then
        start_map="$candidate"
        break
      fi
    done < "$HLDS_DIR/cstrike/mapcycle.txt"
  fi
  echo "Starting ReHLDS on 127.0.0.1:27015 with $MAXPLAYERS slots on $start_map; $remaining seconds remain."
  setsid timeout --signal=TERM --kill-after=30s "${remaining}s" \
    ./hlds_run -game cstrike -console -ip 127.0.0.1 -port 27015 \
    +maxplayers "$MAXPLAYERS" +map "$start_map" +mapcyclefile mapcycle.txt +log on +mp_logecho 1 \
    +hostname "CS 1.6 Public Test Server" +sv_lan 0 +sv_allowdownload 1 \
    +sv_downloadurl "https://raw.githubusercontent.com/KULTHX/Cs16test/main/dashboard/fastdl/cstrike/" +meta list \
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
  local ssh_user ssh_home
  ssh_user="$(id -un)"
  ssh_home="$(getent passwd "$ssh_user" | cut -d: -f6)"
  if [[ -z "$ssh_home" || "$ssh_user" != "runner" ]]; then
    echo "Unexpected GitHub runner account; refusing to configure SSH for $ssh_user." >&2
    return 1
  fi

  if [[ -z "${SSH_AUTHORIZED_KEYS:-}" ]]; then
    echo "No SSH authorized keys are configured." >&2
    return 1
  fi

  sudo install -d -m 0700 -o "$ssh_user" -g "$ssh_user" "$ssh_home/.ssh"
  printf '%s\n' "$SSH_AUTHORIZED_KEYS" | sudo tee "$ssh_home/.ssh/authorized_keys" >/dev/null
  sudo chown "$ssh_user:$ssh_user" "$ssh_home/.ssh/authorized_keys"
  sudo chmod 0600 "$ssh_home/.ssh/authorized_keys"

  if [[ -n "${SSH_HOST_ED25519_PRIVATE_KEY:-}" ]]; then
    printf '%s\n' "$SSH_HOST_ED25519_PRIVATE_KEY" | sudo tee /etc/ssh/ssh_host_ed25519_key >/dev/null
    sudo chmod 0600 /etc/ssh/ssh_host_ed25519_key
    sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key | sudo tee /etc/ssh/ssh_host_ed25519_key.pub >/dev/null
  else
    if [[ ! -s /etc/ssh/ssh_host_ed25519_key ]]; then
      sudo rm -f /etc/ssh/ssh_host_ed25519_key.pub
      sudo ssh-keygen -q -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key
      echo "Generated a per-session SSH host key; login authorized keys remain unchanged."
    elif [[ ! -s /etc/ssh/ssh_host_ed25519_key.pub ]]; then
      sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key | sudo tee /etc/ssh/ssh_host_ed25519_key.pub >/dev/null
    fi
  fi
  sudo chmod 0600 /etc/ssh/ssh_host_ed25519_key
  SSH_HOST_FINGERPRINT="$(sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256 | awk '{print $2}')"

  sudo mkdir -p /run/sshd
  cat > "$SSH_CONFIG" <<EOF
Port 22
ListenAddress 127.0.0.1
HostKey /etc/ssh/ssh_host_ed25519_key
PidFile $SSH_PID_FILE
AuthorizedKeysFile $ssh_home/.ssh/authorized_keys
AllowUsers $ssh_user
PermitRootLogin no
PubkeyAuthentication yes
AuthenticationMethods publickey
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no
UsePAM no
AllowTcpForwarding no
AllowAgentForwarding no
X11Forwarding no
PermitTunnel no
PermitUserEnvironment no
MaxAuthTries 3
MaxSessions 4
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
  echo "SSH daemon is listening on 127.0.0.1:22 (key-only)."
  echo "SSH host key fingerprint: $SSH_HOST_FINGERPRINT"
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

start_bore() {
  local attempt running address
  stop_bore
  printf '\n[%s] Starting Bore SSH tunnel...\n' "$(date -u +%FT%TZ)" >> "$BORE_LOG_FILE"
  if ! timeout 120s docker run -d --rm --name bore --network host \
      ekzhang/bore:0.6.0 local 22 --local-host 127.0.0.1 --to bore.pub >> "$BORE_LOG_FILE" 2>&1; then
    echo "Bore container could not start; the CS 1.6 session will continue." | tee -a "$BORE_LOG_FILE"
    return 1
  fi

  docker logs -f bore >> "$BORE_LOG_FILE" 2>&1 &
  BORE_LOG_PID=$!
  for attempt in $(seq 1 30); do
    running="$(docker inspect -f '{{.State.Running}}' bore 2>/dev/null || true)"
    if [[ "$running" != "true" ]]; then
      echo "Bore exited before publishing an SSH address." | tee -a "$BORE_LOG_FILE"
      stop_bore
      return 1
    fi
    address="$(grep -Eo 'bore\.pub:[0-9]+' "$BORE_LOG_FILE" | tail -n 1 || true)"
    if [[ "$address" =~ ^bore\.pub:([0-9]+)$ ]]; then
      BORE_ADDRESS="$address"
      BORE_PORT="${BASH_REMATCH[1]}"
      echo "BORE SSH TUNNEL READY"
      echo "Public address: $BORE_ADDRESS"
      echo "SSH command: ssh -o IdentitiesOnly=yes -i ~/.ssh/cs16_friend -p $BORE_PORT runner@bore.pub"
      echo "SSH host key fingerprint: $SSH_HOST_FINGERPRINT"
      return 0
    fi
    sleep 2
  done
  echo "Bore did not publish an address within 60 seconds; keeping the game server running." | tee -a "$BORE_LOG_FILE"
  docker logs --tail 50 bore >> "$BORE_LOG_FILE" 2>&1 || true
  stop_bore
  return 1
}

start_server_with_retry
start_playit_with_retry
BORE_RETRY_AT=0
if [[ "$SSH_ENABLED" == "true" ]]; then
  if start_ssh_with_retry; then
    if start_bore; then
      BORE_ENABLED=true
    else
      BORE_RETRY_AT=$((SECONDS + 60))
    fi
  else
    echo "SSH setup failed; the game server and Playit will continue without remote SSH."
    SSH_ENABLED=false
  fi
fi

echo "Self-healing session active. The watchdog checks ReHLDS, Playit, SSH, and Bore every 10 seconds."
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
      stop_bore
      stop_ssh
      if ! start_ssh_with_retry; then
        echo "Watchdog: SSH could not be restarted; disabling the SSH tunnel without stopping the game."
        SSH_ENABLED=false
        BORE_ENABLED=false
      fi
    fi

    if [[ "$SSH_ENABLED" == "true" ]]; then
      bore_running="$(docker inspect -f '{{.State.Running}}' bore 2>/dev/null || true)"
      if [[ "$BORE_ENABLED" == "true" && "$bore_running" != "true" ]]; then
        echo "Watchdog: Bore tunnel stopped; scheduling a reconnect."
        stop_bore
        BORE_ENABLED=false
        BORE_RETRY_AT=$((SECONDS + 30))
      fi

      if [[ "$BORE_ENABLED" != "true" ]] && (( SECONDS >= BORE_RETRY_AT )); then
        if start_bore; then
          BORE_ENABLED=true
        else
          BORE_RETRY_AT=$((SECONDS + 60))
        fi
      fi
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
