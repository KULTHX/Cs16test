#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: REHLDS_VERSION=3.15.0.896 bash scripts/install-rehlds.sh /path/to/hlds"
  exit 2
}

[[ $# -eq 1 ]] || usage

HLDS_DIR="$1"
REHLDS_VERSION="${REHLDS_VERSION:-3.15.0.896}"
GPG_FINGERPRINT="63547829004f07716f7be4856c32c4282e60fb67"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -d "$HLDS_DIR" ]] || fail "HLDS directory does not exist: $HLDS_DIR"
HLDS_DIR="$(cd "$HLDS_DIR" && pwd)"
[[ -f "$HLDS_DIR/hlds_run" ]] || fail "hlds_run is missing. Install the base app 90 server files first."
[[ -f "$HLDS_DIR/engine_i486.so" ]] || fail "Base engine_i486.so is missing. Install the base app 90 server files first."

[[ "$REHLDS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid ReHLDS version: $REHLDS_VERSION"

for cmd in curl gpg unzip install; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Required command is missing: $cmd"
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
export GNUPGHOME="$WORK_DIR/gnupg"
mkdir -m 700 "$GNUPGHOME"

ARCHIVE="rehlds-bin-${REHLDS_VERSION}.zip"
BASE_URL="https://github.com/rehlds/ReHLDS/releases/download/${REHLDS_VERSION}"

echo "[1/4] Downloading ReHLDS ${REHLDS_VERSION}..."
curl --fail --location --retry 3 --retry-delay 2 \
  "${BASE_URL}/${ARCHIVE}" -o "$WORK_DIR/$ARCHIVE"
curl --fail --location --retry 3 --retry-delay 2 \
  "${BASE_URL}/${ARCHIVE}.asc" -o "$WORK_DIR/${ARCHIVE}.asc"

echo "[2/4] Verifying the official ReHLDS release signature..."
gpg --batch --keyserver hkps://keyserver.ubuntu.com \
  --recv-keys "$GPG_FINGERPRINT"
gpg --batch --verify "$WORK_DIR/${ARCHIVE}.asc" "$WORK_DIR/$ARCHIVE"

echo "[3/4] Locating the Linux 32-bit ReHLDS engine..."
mapfile -t ENGINE_PATHS < <(unzip -Z1 "$WORK_DIR/$ARCHIVE" | grep -E '(^|/)engine_i486\.so$' || true)
[[ ${#ENGINE_PATHS[@]} -gt 0 ]] || fail "The release archive does not contain engine_i486.so."

ENGINE_PATH=""
for candidate in "${ENGINE_PATHS[@]}"; do
  if [[ "$candidate" == "bin/linux32/engine_i486.so" || "$candidate" == */bin/linux32/engine_i486.so ]]; then
    ENGINE_PATH="$candidate"
    break
  fi
done

if [[ -z "$ENGINE_PATH" ]]; then
  [[ ${#ENGINE_PATHS[@]} -eq 1 ]] || fail "Multiple engine_i486.so files found; refusing an ambiguous install."
  ENGINE_PATH="${ENGINE_PATHS[0]}"
fi

unzip -p "$WORK_DIR/$ARCHIVE" "$ENGINE_PATH" > "$WORK_DIR/engine_i486.so"
[[ -s "$WORK_DIR/engine_i486.so" ]] || fail "Extracted engine binary is empty."

echo "[4/4] Backing up the current engine and installing ReHLDS..."
BACKUP="$HLDS_DIR/engine_i486.so.stock.$(date -u +%Y%m%dT%H%M%SZ)"
cp -p "$HLDS_DIR/engine_i486.so" "$BACKUP"
install -m 0755 "$WORK_DIR/engine_i486.so" "$HLDS_DIR/engine_i486.so"

echo "ReHLDS ${REHLDS_VERSION} installed."
echo "Original engine backup: $BACKUP"
echo "Confirm the ReHLDS version in the server startup log during the smoke test."
