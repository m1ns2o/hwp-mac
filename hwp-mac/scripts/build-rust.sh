#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PROFILE="${1:-debug}"

cd "${REPO_ROOT}"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo를 찾을 수 없습니다. Rust toolchain을 먼저 설치하세요." >&2
  exit 1
fi

if [[ "${PROFILE}" == "release" ]]; then
  cargo build --lib --release
  echo "RHWP_LIB_SEARCH_PATH=${REPO_ROOT}/target/release"
else
  cargo build --lib
  echo "RHWP_LIB_SEARCH_PATH=${REPO_ROOT}/target/debug"
fi
