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

if [[ -z "${PLAYIT_SECRET_KEY:-}" ]]; then
  echo "PLAYIT_SECRET_KEY is required." >&2
  exit 2
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

cleanup() {
  local status=$?
  trap - EXIT INT TERM
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

start_server_with_retry
start_playit_with_retry

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
