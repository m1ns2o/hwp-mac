#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$APP_DIR/.." && pwd)"

watch_targets=(
  "$APP_DIR/Sources"
  "$APP_DIR/Package.swift"
  "$REPO_DIR/src"
)

build_and_launch() {
  echo "[dev-watch] rebuilding app..."
  "$SCRIPT_DIR/run-app.sh" --bundle-only >/dev/null

  local app_bundle="$APP_DIR/.build/debug/HwpMacApp.app"
  pkill -f "HwpMacApp.app/Contents/MacOS/HwpMacApp" >/dev/null 2>&1 || true
  open -na "$app_bundle"
  echo "[dev-watch] app relaunched"
}

snapshot() {
  find "${watch_targets[@]}" -type f -print0 2>/dev/null \
    | xargs -0 stat -f "%N %m" 2>/dev/null \
    | sort
}

build_and_launch

if command -v fswatch >/dev/null 2>&1; then
  echo "[dev-watch] fswatch detected"
  fswatch -0 "${watch_targets[@]}" | while IFS= read -r -d '' _; do
    build_and_launch
  done
else
  echo "[dev-watch] fswatch not found, using polling"
  last_state="$(snapshot)"
  while true; do
    sleep 1
    current_state="$(snapshot)"
    if [[ "$current_state" != "$last_state" ]]; then
      last_state="$current_state"
      build_and_launch
    fi
  done
fi
